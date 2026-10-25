#!/usr/bin/env bash
# test/test.sh — `ctl test [target…]`. Each app's own suite from its own folder, under the TESTING
# settings of .env. The apps are the rows of scripts/gate/_targets.sh. `e2e` is a separate target
# (test/e2e.sh) and is NOT part of the default run — it opens a throwaway stack.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_targets.sh"
source "$CTL_ROOT/scripts/common/_test-settings.sh"

usage() { print_help "test" "Run test suites across the apps." \
  "test [$(gate_target_names test)]… | test e2e [--keep] [-h]" \
"Targets  (none: every suite below whose folder exists, not e2e)
$(gate_target_help test)
  e2e           the browser suite against a throwaway stack (test/e2e.sh)

What runs, per ecosystem
  python          uv run pytest   (database: the migration round-trip)
  rust            cargo test
  bun             bun run test
  go              go test -race ./...

An app marked db in scripts/gate/_targets.sh runs against this run's own PostgreSQL, a throwaway
container migrated once; each such suite gets its own copy of the migrated database. Set
TEST_DATABASE_URL to use a database you migrated instead, such as a CI service.

Options
  -h, --help      show this help

The TESTING section of .env sets the cores, the compiler jobs and the memory budget; a value in the
shell wins over .env. ctl gate --help lists them."; }

is_help "${1:-}" && { usage; exit 0; }
if [[ ${1:-} == e2e ]]; then shift; test_settings_init; exec bash "$CTL_ROOT/scripts/test/e2e.sh" "$@"; fi
names=()
while (( $# )); do case "$1" in
  -*) die "unknown flag $1 (see ctl test -h)" ;;
  *)  names+=("$1") ;;
esac; shift; done
gate_target_select test ${names[@]+"${names[@]}"}
test_settings_init
# need_database <name> — fill suite_env, the settings a suite runs with. A suite marked `db` in
# _targets.sh gets its own copy of the run's throwaway database (test/_test-database.sh), which starts
# with the first such suite and goes when the run ends. A caller's TEST_DATABASE_URL is used as it is.
# A project whose DATA_SVCS has no postgres, as in a ctl test fixture, starts none.
suite_env=()
need_database() {
  suite_env=()
  gate_target_needs_db "$1" && [[ " ${DATA_SVCS[*]} " == *" postgres "* ]] || return 0
  if [[ -n ${TEST_DATABASE_URL:-} ]]; then suite_env=("DATABASE_URL=$TEST_DATABASE_URL"); return 0; fi
  if ! declare -F test_database_start >/dev/null; then
    source "$CTL_ROOT/scripts/common/_process.sh"; source "$CTL_ROOT/scripts/test/_test-database.sh"
    trap test_database_stop EXIT
    test_database_start
  fi
  mapfile -t suite_env < <(test_database_for "$1")
  (( ${#suite_env[@]} )) || die "no test database settings for the $1 suite"
}
# with_suite_env <command…> — run the command with suite_env exported. Call it inside the suite's
# subshell, so the next suite starts without them.
with_suite_env() { local setting; for setting in ${suite_env[@]+"${suite_env[@]}"}; do export "$setting"; done; "$@"; }
rc=0 ran=0 empty=()
# An app with no test file yet is named, not failed: pytest exits 5 and vitest exits 1 on an empty
# suite, which would turn the floor red on day one. The suite is found by the names 10c mandates
# (test_*.py, *_test.py, *.test.*, *.spec.*); a suite under other names is skipped with the same
# warning, so keep the names. cargo test and go test pass an empty suite on their own.
has_tests() { [[ -n $(find "$1" -path '*/node_modules' -prune -o -path '*/e2e' -prune -o -path '*/.venv' -prune -o \( -name 'test_*.py' -o -name '*_test.py' -o -name '*.test.*' -o -name '*.spec.*' \) -print -quit 2>/dev/null) ]]; }
no_tests_yet() { warn "$1: no test file yet — nothing ran here"; empty+=("$1"); }
for row in ${GATE_SELECTED[@]+"${GATE_SELECTED[@]}"}; do
  read -r name dir ecosystem <<< "$row"
  case "$ecosystem" in
    python) step "$dir (pytest)";      has_tests "$dir" || { no_tests_yet "$dir"; continue; }; need_database "$name"
            ( require_tools uv && cd "$dir" && with_suite_env uv run pytest ) || rc=1 ;;
    rust)   step "$dir (cargo test)";  need_database "$name"; ( require_tools cargo && cd "$dir" && with_suite_env cargo test ) || rc=1 ;;
    bun)    step "$dir (bun run test)"; has_tests "$dir" || { no_tests_yet "$dir"; continue; }; need_database "$name"
            ( require_tools bun && cd "$dir" && with_suite_env bun run test ) || rc=1 ;;
    # -race always: a data race is cheapest to find here (10c). It needs cgo, so a machine without a
    # C compiler fails by name instead of skipping the race detector quietly.
    go)     step "$dir (go test -race)"; need_database "$name"; ( require_tools go && cd "$dir" && with_suite_env go test -race ./... ) || rc=1 ;;
    *)      die "scripts/gate/_targets.sh gives $name the ecosystem '$ecosystem'; ctl test knows python, rust, bun and go" ;;
  esac
  ran=$(( ran + 1 ))
done
# The closing line says what ran. "tests passed" is printed only when a suite executed; an empty
# run says so in its own words, because a green line over nothing is how a gate stops being read.
if (( rc != 0 )); then err "tests failed"
elif (( ran == 0 )); then warn "no suite ran — nothing proved; the rung passes until the first test lands"
else ok "tests passed — $ran suite(s) ran"; (( ${#empty[@]} )) && warn "no test file yet in: ${empty[*]}"; fi
exit $rc
