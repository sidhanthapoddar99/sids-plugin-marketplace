#!/usr/bin/env bash
# ctl status — config doctor. Checks .env schema, tool availability, data-core reachability.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
rc=0

echo "▸ env"
if [[ -x scripts/check-env.sh ]]; then bash scripts/check-env.sh || rc=1
else echo "  ! scripts/check-env.sh missing"; rc=1; fi

echo "▸ tools"
for t in mise docker uv bun; do
  if command -v "$t" >/dev/null 2>&1; then echo "  ✓ $t"; else echo "  ✗ $t (missing)"; rc=1; fi
done

echo "▸ data core"
[[ -f .env ]] && { set -a; source .env; set +a; }
proj="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
for svc in postgres redis; do
  s=$(docker inspect -f '{{.State.Health.Status}}' "${proj}-${svc}" 2>/dev/null || echo "down")
  echo "  ${svc}: ${s}"
done

exit $rc
