#!/usr/bin/env bash
# Stop GLM-5.3-Flash-EXL3 on both DGX Sparks and free their GPU memory.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
[[ -f "$HERE/config.sh" ]] && source "$HERE/config.sh"

HEAD="${HEAD:-localhost}"
WORKER="${WORKER:-}"
REMOTE_DIR="${REMOTE_DIR:-$HOME/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold}"
CONTAINER="${CONTAINER:-glm53-flash-tf}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0")

Stop both ranks and free their GPU memory.

Environment (or config.sh):
  HEAD=$HEAD
  WORKER=${WORKER:-<unset: the recipe stops every worker configured in local.sh>}
  REMOTE_DIR=$REMOTE_DIR
  CONTAINER=$CONTAINER
EOF
}

for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $a (try --help)" ;;
  esac
done

ssh "${SSH_OPTS[@]}" "$HEAD" true 2>/dev/null || die "cannot ssh to $HEAD without a password"
ssh "${SSH_OPTS[@]}" "$HEAD" "cd $(printf '%q' "$REMOTE_DIR") && ./stop.sh"

printf '\nRemaining containers:\n'
ssh "${SSH_OPTS[@]}" "$HEAD" "docker ps -a --format '{{.Names}} {{.Status}}' | grep $(printf '%q' "$CONTAINER") || echo '  head:   none'"
if [[ -n "$WORKER" ]]; then
  ssh "${SSH_OPTS[@]}" "$WORKER" "docker ps -a --format '{{.Names}} {{.Status}}' | grep $(printf '%q' "$CONTAINER") || echo '  worker: none'"
fi
