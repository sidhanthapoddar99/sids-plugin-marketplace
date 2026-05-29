#!/usr/bin/env bash
# dev-host.sh — `ctl dev`. Ensure the data core, then run apps on the host with hot reload.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "dev" "Run apps on the host with hot reload; auto-starts the data core." \
  'dev [target] [-h]' \
"Arguments
  target          all (default) | backend | frontend   (honored by process-compose)

Options
  -h, --help      show this help

Brings up postgres+redis (with ports) in containers, waits for health, then runs the
apps as host processes. Uses process-compose if process-compose.yaml exists, else a
bash fallback (fine for ≤2 procs; prefer process-compose past that)."; }

is_help "${1:-}" && { usage; exit 0; }
require_env; require_tools mise docker

step "ensuring data core (with ports)…"
dc -f "$DOCKER_DIR/compose.m.expose.yaml" up -d "${DATA_SVCS[@]}"
wait_healthy "${DATA_SVCS[@]}" 60 || warn "health poll failed — continuing anyway."

if command -v process-compose >/dev/null 2>&1 && [[ -f process-compose.yaml ]]; then
  exec process-compose up "$@"
fi

step "starting host processes — Ctrl-C stops all"
prefix() { local t="$1" c="$2"; while IFS= read -r l; do printf '%s[%s]%s %s\n' "$c" "$t" "$C_RESET" "$l"; done; }
( cd apps/backend  && uv run uvicorn "${BACKEND_MODULE:-app.main}":app --reload \
    --host "${PYTHON_HOST:-0.0.0.0}" --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " "$C_YEL" ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" "$C_CYN" ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
