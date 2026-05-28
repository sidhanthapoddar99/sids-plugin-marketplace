#!/usr/bin/env bash
# ctl migrate {up|down|new "<msg>"|status} — Alembic migrations (the backend owns DDL).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

sub="${1:-}"; shift || true
case "$sub" in
  new)    [[ -n "${1:-}" ]] || { echo "✗ usage: ctl migrate new \"<message>\"" >&2; exit 1; }
          ( cd apps/backend && uv run alembic revision -m "$1" ) ;;
  up)     ( cd apps/backend && uv run alembic upgrade head ) ;;
  down)   ( cd apps/backend && uv run alembic downgrade -1 ) ;;
  status) ( cd apps/backend && uv run alembic current ) ;;
  *)      echo "✗ unknown migrate subcommand: ${sub:-<none>} (up|down|new|status)" >&2; exit 1 ;;
esac
