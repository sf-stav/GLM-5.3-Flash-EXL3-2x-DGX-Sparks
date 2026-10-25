#!/usr/bin/env bash
# Follow the GLM-5.3-Flash-EXL3 server logs on one or both DGX Sparks.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
[[ -f "$HERE/config.sh" ]] && source "$HERE/config.sh"

HEAD="${HEAD:-localhost}"
WORKER="${WORKER:-}"
CONTAINER="${CONTAINER:-glm53-flash-tf}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [head|worker|both] [options]

Follow rank logs continuously (Ctrl-C to stop following).

Options:
  -n, --lines N      Show the last N lines first (default: 100)
      --timestamps   Add docker timestamps
      --no-follow    Print the tail and exit
  -h, --help         Show this help

Environment (or config.sh):
  HEAD=$HEAD
  WORKER=${WORKER:-<unset>}
  CONTAINER=$CONTAINER

Examples:
  ./logs.sh                 # both ranks, prefixed
  ./logs.sh head -n 500
  ./logs.sh worker --timestamps
  ./logs.sh both --no-follow
EOF
}

target=both; lines=100; follow=1; timestamps=0
while (($#)); do
  case "$1" in
    head|worker|both) target=$1; shift ;;
    -n|--lines) [[ $# -ge 2 ]] || die "--lines needs a value"; lines=$2; shift 2 ;;
    --timestamps) timestamps=1; shift ;;
    --no-follow) follow=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done
[[ "$target" == head || -n "$WORKER" ]] || die "WORKER is not set: use 'head', or set WORKER in config.sh"

flags=("--tail" "$lines")
(( follow )) && flags+=(-f)
(( timestamps )) && flags+=(-t)

run_head() {
  ssh "${SSH_OPTS[@]}" "$HEAD" "docker logs $(printf '%q ' "${flags[@]}") $(printf '%q' "$CONTAINER") 2>&1" \
    | sed -u 's/^/[head]   /'
}
run_worker() {
  ssh "${SSH_OPTS[@]}" "$WORKER" "docker logs $(printf '%q ' "${flags[@]}") $(printf '%q' "$CONTAINER") 2>&1" \
    | sed -u 's/^/[worker] /'
}

case "$target" in
  head) run_head ;;
  worker) run_worker ;;
  both)
    if (( ! follow )); then
      run_head
      printf '\n'
      run_worker
      exit 0
    fi
    p1=; p2=
    cleanup() { [[ -n "$p1" ]] && kill "$p1" 2>/dev/null || true; [[ -n "$p2" ]] && kill "$p2" 2>/dev/null || true; }
    trap cleanup INT TERM EXIT
    run_head & p1=$!
    run_worker & p2=$!
    wait -n || true
    ;;
esac
