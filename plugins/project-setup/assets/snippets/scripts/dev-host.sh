#!/usr/bin/env bash
# dev-host.sh — `ctl dev`. Ensure the data core (if any), then run apps on the host with hot reload.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "dev" "Run apps on the host with hot reload; auto-starts the data core." \
  'dev [target] [-h]' \
"Arguments
  target          all (default) | backend | frontend   (honored by process-compose)

Options
  -h, --help      show this help

With a data core (DATA_SVCS set), brings up those services in containers WITH ports
(via the expose_data modifier), waits for health, then runs the apps as host processes.
With no data core (DATA_SVCS empty) it just runs the host processes. Uses process-compose
if process-compose.yaml exists, else a bash fallback (fine for ≤2 procs)."; }

is_help "${1:-}" && { usage; exit 0; }
require_env; require_tools mise

# data core (skipped cleanly when DATA_SVCS is empty — no-data-core projects)
if (( ${#DATA_SVCS[@]} )); then
  require_tools docker
  step "ensuring data core (with ports)…"
  dc -f "$DOCKER_DIR/compose.m.expose_data.yaml" up -d "${DATA_SVCS[@]}"
  wait_healthy "${DATA_SVCS[@]}" 60 || warn "health poll failed — continuing anyway."
fi

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
