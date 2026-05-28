#!/usr/bin/env bash
# ctl test — run backend + frontend suites. Runs both even if one fails; exits non-zero on any failure.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

rc=0
echo "▸ backend tests…";  ( cd apps/backend  && uv run pytest "$@" ) || rc=1
echo "▸ frontend tests…"; ( cd apps/frontend && bun test ) || rc=1
exit $rc
