#!/usr/bin/env bash
# ctl clean — wipe caches + data volumes (asks first).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

cat >&2 <<'EOF'
This will: docker compose down -v (DROPS data volumes), remove node_modules/dist/.vite, clear __pycache__.
EOF
read -r -p "Continue? [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "! aborted." >&2; exit 0; }

docker compose -f docker/compose.yaml down -v 2>/dev/null || true
rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
echo "✓ clean."
