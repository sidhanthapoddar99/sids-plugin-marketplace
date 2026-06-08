#!/usr/bin/env bash
# container/ps.sh — `ctl ps`. What's running, in two sections: containers first, then the
# host dev processes `ctl dev` started (found by what's listening on the dev ports).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "ps" "Show what's running: containers, then host dev processes." \
  'ps [-h]' \
"Options
  -h, --help      show this help

Lists docker compose containers first, then the host processes 'ctl dev' started — resolved
from what's listening on the dev ports (PYTHON_PORT / FRONTEND_PORT), or from process-compose
if that's the runner. Read-only; works without .env (falls back to default ports)."; }

is_help "${1:-}" && { usage; exit 0; }
[[ -f .env ]] && { set -a; source .env; set +a; }     # soft load — ps must never die

section "containers"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then dc ps
else say "${C_DIM}docker not reachable${C_RESET}"; fi

printf '\n'
section "host dev processes"
if command -v process-compose >/dev/null 2>&1 && process-compose process list >/dev/null 2>&1; then
  process-compose process list                         # process-compose is the runner — it knows
else
  printf '  %s%-7s %-6s %s%s\n' "$C_DIM" "PID" "PORT" "COMMAND" "$C_RESET"
  any=0
  for p in "${PYTHON_PORT:-8000}" "${FRONTEND_PORT:-3000}"; do
    pid=$(port_pid "$p"); [[ -n $pid ]] || continue
    cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -1); cmd="${cmd:0:64}"
    printf '  %s%-7s%s %-6s %s\n' "$C_GRN" "$pid" "$C_RESET" "$p" "$cmd"; any=1
  done
  (( any )) || say "${C_DIM}none — ctl dev not running (no dev port listening)${C_RESET}"
fi
