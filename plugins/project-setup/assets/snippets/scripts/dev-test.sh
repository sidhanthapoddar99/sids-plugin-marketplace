#!/usr/bin/env bash
# dev-test.sh — `ctl test`. Run backend + frontend suites.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "test" "Run backend + frontend test suites." \
  'test [backend|frontend] [-h]' \
"Arguments
  (none)          run both suites
  backend         pytest only
  frontend        bun test only

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target="${1:-all}"; rc=0
run_be() { step "backend tests";  ( cd apps/backend  && uv run pytest ) || rc=1; }
run_fe() { step "frontend tests"; ( cd apps/frontend && bun test ) || rc=1; }
case "$target" in
  all)      run_be; run_fe ;;
  backend)  run_be ;;
  frontend) run_fe ;;
  *)        die "unknown target: $target (all|backend|frontend)" ;;
esac
(( rc == 0 )) && ok "tests passed" || err "tests failed"
exit $rc
