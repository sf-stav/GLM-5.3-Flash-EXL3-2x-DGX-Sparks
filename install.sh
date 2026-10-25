#!/usr/bin/env bash
# One-time setup on the head Spark: clone Mia's recipe, add this repo's streaming patch, configure it, and prepare
# both Sparks (image on each, checkpoint on the head and a copy on the worker).
#
# Run this on the head Spark. start.sh/stop.sh/logs.sh may be run from anywhere that can ssh to HEAD.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
[[ -f "$HERE/config.sh" ]] && source "$HERE/config.sh"

RECIPE_REPO="${RECIPE_REPO:-https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold.git}"
REMOTE_DIR="${REMOTE_DIR:-$HOME/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold}"
WORKER="${WORKER:-}"
FABRIC_PEER="${FABRIC_PEER:-}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-9101}"
STREAM_CALLS="${STREAM_CALLS:-1}"
PATCH="$HERE/patches/0123-glm-stream-calls.patch"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[install.sh] %s\n' "$*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-prepare]

Run on the head Spark. Clones the upstream recipe into REMOTE_DIR if it is not there, copies
patches/0123-glm-stream-calls.patch into its patches/, writes the settings into scripts/local.sh, appends the
TF_GLM_STREAM_CALLS switch to scripts/config.sh, then runs scripts/prepare.sh.

Options:
  --no-prepare   Set the recipe up but do not download/build/prepare yet
  -h, --help     Show this help

Environment (or config.sh):
  RECIPE_REPO=$RECIPE_REPO
  REMOTE_DIR=$REMOTE_DIR
  WORKER=$WORKER
  FABRIC_PEER=$FABRIC_PEER
  HOST=$HOST
  PORT=$PORT
  STREAM_CALLS=$STREAM_CALLS
EOF
}

prepare=1
for a in "$@"; do
  case "$a" in
    --no-prepare) prepare=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $a (try --help)" ;;
  esac
done

[[ -n "$WORKER" ]] || die "set WORKER to the second Spark's ssh target (config.sh or the environment)"
[[ "$STREAM_CALLS" == 0 || "$STREAM_CALLS" == 1 ]] || die "STREAM_CALLS is 0 or 1, not $STREAM_CALLS"
[[ -f "$PATCH" ]] || die "missing $PATCH"

replace_key() {  # file key value: replace KEY=... or append KEY=value
  local file=$1 key=$2 value=$3 tmp found=0 line
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s=%s\n' "$key" "$value"
      found=1
    else
      printf '%s\n' "$line"
    fi
  done < "$file" > "$tmp"
  (( found )) || printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

if [[ -d "$REMOTE_DIR/.git" ]]; then
  log "Using the recipe already cloned at $REMOTE_DIR"
elif [[ -e "$REMOTE_DIR" ]]; then
  die "$REMOTE_DIR exists but is not a git clone; move it away or set REMOTE_DIR"
else
  log "Cloning $RECIPE_REPO into $REMOTE_DIR"
  git clone --depth 1 "$RECIPE_REPO" "$REMOTE_DIR"
fi

log "Installing $(basename "$PATCH")"
cp "$PATCH" "$REMOTE_DIR/patches/"

local_sh="$REMOTE_DIR/scripts/local.sh"
if [[ ! -f "$local_sh" ]]; then
  cp "$REMOTE_DIR/scripts/local.sh.example" "$local_sh"
fi
replace_key "$local_sh" WORKER "$WORKER"
[[ -n "$FABRIC_PEER" ]] && replace_key "$local_sh" FABRIC_PEER "$FABRIC_PEER"
replace_key "$local_sh" HOST "$HOST"
replace_key "$local_sh" PORT "$PORT"
log "Wrote WORKER, FABRIC_PEER, HOST and PORT into $local_sh"

cfg="$REMOTE_DIR/scripts/config.sh"
if ! grep -q 'TF_GLM_STREAM_CALLS' "$cfg"; then
  log "Adding TF_GLM_STREAM_CALLS to $cfg"
  cat >> "$cfg" <<'EOF'

# Added by sf-stav/glm53flash: stream GLM tool calls as they are written (patches/0123-glm-stream-calls.patch).
# 1: header and argument fragments as they arrive (OpenAI-style), so a large write/edit call does not leave the
# stream silent for tens of seconds; a call cut by the token limit is then sent in part, marked finish_reason
# "length". 0: the recipe's whole-call deltas. STREAM_CALLS=0 in scripts/local.sh or the environment turns it off.
STREAM_CALLS="${STREAM_CALLS:-1}"
export TF_GLM_STREAM_CALLS="${TF_GLM_STREAM_CALLS:-$STREAM_CALLS}"
EOF
fi

if (( prepare )); then
  log "Preparing both Sparks (the new patch changes the image hash, so prepare.sh builds the image locally)"
  ( cd "$REMOTE_DIR" && ./scripts/prepare.sh )
else
  log "Skipping prepare.sh (--no-prepare)"
fi

cat <<EOF

Done. Next:
  ./start.sh              # or: ./start.sh --restart
  ./logs.sh               # both ranks, prefixed
  ./stop.sh

The recipe is at $REMOTE_DIR. The API is served on ${HOST}:${PORT}.
EOF
