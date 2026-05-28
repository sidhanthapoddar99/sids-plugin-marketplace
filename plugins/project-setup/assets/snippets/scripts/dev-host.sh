#!/usr/bin/env bash
# Host dev loop — bash fallback (≤2 processes; prefer process-compose past that).
# Runs apps on the host with hot reload. Ctrl-C stops all. Assumes the data core is already up
# (ctl dev ensures that before exec-ing here).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
[[ -f .env ]] && { set -a; source .env; set +a; }

prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }

echo "▸ starting services on host. Ctrl-C kills all."
( cd apps/backend && uv run uvicorn "${BACKEND_MODULE:-app.main}":app --reload \
    --host "${PYTHON_HOST:-0.0.0.0}" --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
