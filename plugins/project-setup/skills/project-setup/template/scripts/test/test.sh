#!/usr/bin/env bash
# test/test.sh — `ctl test [app]`. Each app's own suite from its own folder. `e2e` is a separate
# target (test/e2e.sh) and is NOT part of the default run — it opens a throwaway stack.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "test" "Run test suites across the apps." \
  'test [api|engine|landing|app|docs|dashboard|cli|database|e2e] [-h]' \
"Arguments
  (none)          every suite below (not e2e)
  api             apps/example-api-python               — uv run pytest
  database        apps/database/postgres — uv run pytest (migration round-trip; needs the data core up)
  engine          apps/example-engine-rust            — cargo test
  landing, app, docs   apps/example-multi-web-app/<x>      — bun test
  dashboard       apps/example-dashboard-nextjs         — bun test
  cli             apps/example-tui-go               — go test ./...
  e2e             the browser suite against a throwaway stack (test/e2e.sh)

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target="${1:-all}"; rc=0; ran=0; empty=()
# `all` skips an app folder that is absent, because a repo deletes the apps it does not have. An
# explicit target must exist: `ctl test api` on a missing folder is a typo, and a typo that passes
# teaches the caller nothing.
need_dir() { [[ -d $1 ]] || die "$1 not found — the target '$target' has no folder to test"; }
# An app with no test file yet is named, not failed: pytest exits 5 and vitest exits 1 on an empty
# suite, which would turn the floor red on day one. The suite is found by the names 10c mandates
# (test_*.py, *_test.py, *.test.*, *.spec.*); a suite under other names is skipped with the same
# warning, so keep the names. cargo test and go test pass an empty suite on their own.
has_tests() { [[ -n $(find "$1" -path '*/node_modules' -prune -o -path '*/e2e' -prune -o -path '*/.venv' -prune -o \( -name 'test_*.py' -o -name '*_test.py' -o -name '*.test.*' -o -name '*.spec.*' \) -print -quit 2>/dev/null) ]]; }
no_tests_yet() { warn "$1: no test file yet — nothing ran here"; empty+=("$1"); }
run_py() { [[ -d $1 ]] || return 0; step "$1 (pytest)";      has_tests "$1" || { no_tests_yet "$1"; return 0; }; ran=$(( ran + 1 )); ( cd "$1" && uv run pytest ) || rc=1; }
run_rs() { [[ -d $1 ]] || return 0; step "$1 (cargo test)";  ran=$(( ran + 1 )); ( cd "$1" && cargo test ) || rc=1; }
run_js() { [[ -d $1 ]] || return 0; step "$1 (bun run test)"; has_tests "$1" || { no_tests_yet "$1"; return 0; }; ran=$(( ran + 1 )); ( cd "$1" && bun run test ) || rc=1; }
run_go() { [[ -d $1 ]] || return 0; step "$1 (go test)";     ran=$(( ran + 1 )); ( cd "$1" && go test ./... ) || rc=1; }
# [ADAPT] APPS. `all` lists every app the repo can hold; delete the lines for apps the repo dropped.
# The single-frontend shape is listed beside the group, because a repo keeps one of the two and
# a default run that never lists the kept one is green for work it never did.
case "$target" in
  all)      run_py apps/example-api-python; run_py apps/database/postgres; run_rs apps/example-engine-rust
            run_js apps/example-single-web-app-vite
            run_js apps/example-multi-web-app/landing; run_js apps/example-multi-web-app/app; run_js apps/example-multi-web-app/docs
            run_js apps/example-dashboard-nextjs; run_go apps/example-tui-go ;;
  api)      need_dir apps/example-api-python;        run_py apps/example-api-python ;;
  database) need_dir apps/database/postgres;         run_py apps/database/postgres ;;
  engine)   need_dir apps/example-engine-rust;       run_rs apps/example-engine-rust ;;
  landing)  need_dir apps/example-multi-web-app/landing; run_js apps/example-multi-web-app/landing ;;
  app)      need_dir apps/example-multi-web-app/app; run_js apps/example-multi-web-app/app ;;
  single)   need_dir apps/example-single-web-app-vite; run_js apps/example-single-web-app-vite ;;
  docs)     need_dir apps/example-multi-web-app/docs; run_js apps/example-multi-web-app/docs ;;
  dashboard) need_dir apps/example-dashboard-nextjs; run_js apps/example-dashboard-nextjs ;;
  cli)      need_dir apps/example-tui-go;            run_go apps/example-tui-go ;;
  e2e)      exec bash "$CTL_ROOT/scripts/test/e2e.sh" "${@:2}" ;;
  *)        die "unknown target: $target (all|api|engine|landing|app|docs|dashboard|cli|database|single|e2e)" ;;
esac
# The closing line says what ran. "tests passed" is printed only when a suite executed; an empty
# run says so in its own words, because a green line over nothing is how a gate stops being read.
if (( rc != 0 )); then err "tests failed"
elif (( ran == 0 )); then warn "no suite ran — nothing proved; the rung passes until the first test lands"
else ok "tests passed — $ran suite(s) ran"; (( ${#empty[@]} )) && warn "no test file yet in: ${empty[*]}"; fi
exit $rc
