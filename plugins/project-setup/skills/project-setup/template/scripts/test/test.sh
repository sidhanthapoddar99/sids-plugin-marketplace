#!/usr/bin/env bash
# test/test.sh — `ctl test [app]`. Each app's own suite from its own folder. `e2e` is a separate
# target (test/e2e.sh) and is NOT part of the default run — it opens a throwaway stack.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "test" "Run test suites across the apps." \
  'test [api|engine|landing|app|docs|dashboard|cli|database|e2e] [-h]' \
"Arguments
  (none)          every suite below (not e2e)
  api             apps/api               — uv run pytest
  database        apps/database/postgres — uv run pytest (migration round-trip; needs the data core up)
  engine          apps/engine            — cargo test
  landing, app, docs   apps/multi-web-app/<x>      — bun test
  dashboard       apps/dashboard         — bun test
  cli             apps/cli               — go test ./...
  e2e             the browser suite against a throwaway stack (test/e2e.sh)

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target="${1:-all}"; rc=0
run_py() { [[ -d $1 ]] || return 0; step "$1 (pytest)";      ( cd "$1" && uv run pytest ) || rc=1; }
run_rs() { [[ -d $1 ]] || return 0; step "$1 (cargo test)";  ( cd "$1" && cargo test ) || rc=1; }
run_js() { [[ -d $1 ]] || return 0; step "$1 (bun test)";    ( cd "$1" && bun test ) || rc=1; }
run_go() { [[ -d $1 ]] || return 0; step "$1 (go test)";     ( cd "$1" && go test ./... ) || rc=1; }
case "$target" in
  all)      run_py apps/api; run_py apps/database/postgres; run_rs apps/engine; run_js apps/multi-web-app/landing; run_js apps/multi-web-app/app; run_js apps/multi-web-app/docs; run_js apps/dashboard; run_go apps/cli ;;
  api)      run_py apps/api ;;
  database) run_py apps/database/postgres ;;
  engine)   run_rs apps/engine ;;
  landing)  run_js apps/multi-web-app/landing ;;
  app)      run_js apps/multi-web-app/app ;;
  docs)     run_js apps/multi-web-app/docs ;;
  dashboard) run_js apps/dashboard ;;
  cli)      run_go apps/cli ;;
  e2e)      exec bash "$CTL_ROOT/scripts/test/e2e.sh" "${@:2}" ;;
  *)        die "unknown target: $target (all|api|engine|landing|app|docs|dashboard|cli|database|e2e)" ;;
esac
(( rc == 0 )) && ok "tests passed" || err "tests failed"
exit $rc
