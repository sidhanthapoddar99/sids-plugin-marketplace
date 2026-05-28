#!/usr/bin/env bash
# ctl build — build frontend assets + backend image (local/dev tags).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
[[ -f .env ]] && { set -a; source .env; set +a; }

echo "▸ building frontend…"; ( cd apps/frontend && bun run build )
echo "▸ building backend image…"; docker build -t "${COMPOSE_PROJECT_NAME:-myapp}-backend:dev" apps/backend
