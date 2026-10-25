#!/usr/bin/env bash
# Start GLM-5.3-Flash-EXL3 on the two DGX Sparks (runs the upstream recipe's start.sh on HEAD over ssh).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
[[ -f "$HERE/config.sh" ]] && source "$HERE/config.sh"

HEAD="${HEAD:-localhost}"
WORKER="${WORKER:-}"
REMOTE_DIR="${REMOTE_DIR:-$HOME/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-9101}"
MODEL="${MODEL:-GLM-5.3-Flash-EXL3}"
STREAM_CALLS="${STREAM_CALLS:-1}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- extra start.sh args]

Start the model server on both Sparks (API on ${HOST}:${PORT}).

Options:
  -r, --restart             Restart both ranks (use after changing settings)
  -c, --context N           Context window in tokens (default recipe value: 1048576)
  -s, --stream-calls 0|1    Stream GLM tool-call arguments (patch 0123; default: $STREAM_CALLS)
  -n, --dry-run             Show what the recipe would do; change nothing
  -v, --validate            Query /v1/models after startup
  -h, --help                Show this help

Environment (or config.sh):
  HEAD=$HEAD
  WORKER=${WORKER:-<unset: scripts/local.sh decides>}
  REMOTE_DIR=$REMOTE_DIR
  HOST=$HOST
  PORT=$PORT
  MODEL=$MODEL
  STREAM_CALLS=$STREAM_CALLS

Examples:
  ./start.sh
  ./start.sh --restart
  ./start.sh -c 524288 --restart
  ./start.sh -s 0 --restart        # back to whole tool-call deltas
  ./start.sh --validate
EOF
}

passthru=(); restart=0; dry=0; context=""; validate=0; stream_calls="$STREAM_CALLS"
while (($#)); do
  case "$1" in
    -r|--restart) restart=1; shift ;;
    -c|--context) [[ $# -ge 2 ]] || die "--context needs a value"; context=$2; shift 2 ;;
    -s|--stream-calls) [[ $# -ge 2 ]] || die "--stream-calls needs 0 or 1"; stream_calls=$2; shift 2 ;;
    -n|--dry-run) dry=1; shift ;;
    -v|--validate) validate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; passthru+=("$@"); break ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) passthru+=("$1"); shift ;;
  esac
done
[[ "$stream_calls" == 0 || "$stream_calls" == 1 ]] || die "--stream-calls is 0 or 1, not $stream_calls"

remote_args=()
(( restart )) && remote_args+=(restart)
remote_args+=("${passthru[@]}")

ssh "${SSH_OPTS[@]}" "$HEAD" true 2>/dev/null || die "cannot ssh to $HEAD without a password"
if [[ -n "$WORKER" ]]; then
  ssh "${SSH_OPTS[@]}" "$WORKER" true 2>/dev/null || die "cannot ssh to $WORKER without a password"
fi

cmd="cd $(printf '%q' "$REMOTE_DIR") && export PATH=\"\$HOME/.local/bin:\$PATH\" &&"
envs=("PORT=$PORT" "HOST=$HOST" "TF_GLM_STREAM_CALLS=$stream_calls")
(( dry )) && envs+=(DRY_RUN=1)
[[ -n "$context" ]] && envs+=("CONTEXT=$context")
for e in "${envs[@]}"; do cmd+=" $(printf '%q' "$e")"; done
cmd+=" ./start.sh"
for a in "${remote_args[@]}"; do cmd+=" $(printf '%q' "$a")"; done

printf 'Starting on %s (worker %s)...\n' "$HEAD" "${WORKER:-from scripts/local.sh}"
ssh "${SSH_OPTS[@]}" "$HEAD" "$cmd"

if (( validate )); then
  printf '\nRunning validation...\n'
  ssh "${SSH_OPTS[@]}" "$HEAD" "curl -fsS http://127.0.0.1:$PORT/v1/models" ||
    die "server is not answering on $HEAD:$PORT"
  printf '\n'
fi

(( dry )) || printf '\nAPI: http://%s:%s/v1  (model: %s, listening on %s)\n' "${HEAD##*@}" "$PORT" "$MODEL" "$HOST"
