#!/usr/bin/env bash
# gate/lint.sh — `ctl gate lint [target…] [--staged]`. Rung 1: every linter over every app; first because it is the cheapest answer in the ladder.
# One implementation, two callers: the ladder runs it with no target (the whole repo) or with the
# targets a changed-only run reaches; by name it takes targets and --staged (the pre-commit hook).
# -q/--quiet is the shared gate capture. The apps are the rows of scripts/gate/_targets.sh.
#
# TWO PASSES. The linters that compile nothing (ruff, cargo fmt, oxlint, gofmt) run on every target
# first. The ones that compile (clippy, golangci-lint) run only when all of those passed, because a
# formatting slip should fail in seconds, not after a Clippy build.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"
source "$CTL_ROOT/scripts/gate/_targets.sh"
source "$CTL_ROOT/scripts/common/_test-settings.sh"
gate_quiet_reexec "$@"

usage() { print_help "gate lint" "Lint every app (non-mutating)." \
  "gate lint [$(gate_target_names lint)]… [--staged] [-h]" \
"Targets  (none: every target whose folder exists; scripts/gate/_targets.sh lists them)
$(gate_target_help lint)

What runs, per ecosystem  (the cheap pass on every target first, then the compiling pass)
  python          ruff check  (reads [tool.ruff] in pyproject.toml: C901 at 10)
  rust            cargo fmt --check, then clippy -D warnings -D clippy::cognitive_complexity  (clippy.toml)
  bun             bun run lint  (oxlint, reads .oxlintrc.json)
  go              gofmt -l, then golangci-lint run  (reads .golangci.yml: gocyclo at 10)

Options
  --staged        only targets with a git-staged file under them
  -q, --quiet     counts only when green; a red run prints in full
  -h, --help      show this help

Cores and compiler jobs come from the TESTING section of .env (ctl gate --help)."; }

is_help "${1:-}" && { usage; exit 0; }
staged=0 names=()
while (( $# )); do case "$1" in
  --staged) staged=1 ;;
  -*)       die "unknown flag $1 (see ctl gate lint -h)" ;;
  *)        names+=("$1") ;;
esac; shift; done
gate_target_select lint ${names[@]+"${names[@]}"}
test_settings_init
rc=0 ran=0 compiling=()
# touched <dir> — with --staged: 0 only if a staged file lives under <dir>
touched() { (( staged )) || return 0; git diff --cached --name-only --diff-filter=ACMR -- "$1" | grep -q .; }
# has_python <dir> — a Python file to lint. A folder kept for another tool (the database's SQL
# migrations) has none until its first Python suite lands, and that is said, not passed silently.
has_python() { [[ -n $(find "$1" -path '*/.venv' -prune -o -path '*/node_modules' -prune -o -name '*.py' -print -quit 2>/dev/null) ]]; }
# gofmt_clean — gofmt -l lists the files it would change; name them, because a red with no file is no answer
gofmt_clean() {
  local files file; files=$(gofmt -l .) || return
  [[ -n $files ]] || return 0
  while IFS= read -r file; do printf 'not gofmt-formatted: %s\n' "$file" >&2; done <<< "$files"
  return 1
}

# The cheap pass. Each linter reads the app's own config, which the template ships with the
# complexity floor set; a tool run without its config reports only its defaults.
for row in ${GATE_SELECTED[@]+"${GATE_SELECTED[@]}"}; do
  read -r name dir ecosystem <<< "$row"
  touched "$dir" || continue
  case "$ecosystem" in
    python) has_python "$dir" || { warn "$dir: no Python file yet — nothing to lint here"; continue; }
            step "lint $dir (ruff)";          ( require_tools uv && cd "$dir" && uv run ruff check . ) || rc=1 ;;
    rust)   step "lint $dir (cargo fmt)";     ( require_tools cargo && cd "$dir" && cargo fmt --check ) || rc=1; compiling+=("$row") ;;
    bun)    step "lint $dir (bun run lint)";  ( require_tools bun && cd "$dir" && bun run lint ) || rc=1 ;;
    go)     step "lint $dir (gofmt)";         ( require_tools go && cd "$dir" && gofmt_clean ) || rc=1; compiling+=("$row") ;;
    *)      die "scripts/gate/_targets.sh gives $name the ecosystem '$ecosystem'; lint knows python, rust, bun and go" ;;
  esac
  ran=$(( ran + 1 ))
done
if (( rc != 0 )); then
  if (( ${#compiling[@]} )); then
    skipped=(); for row in "${compiling[@]}"; do read -r name _ <<< "$row"; skipped+=("$name"); done
    err "NOT RUN, because a cheap lint above failed first: clippy and golangci-lint on ${skipped[*]}"
  fi
  err "gate lint RED"; exit 1
fi

# The compiling pass.
for row in ${compiling[@]+"${compiling[@]}"}; do
  read -r name dir ecosystem <<< "$row"
  case "$ecosystem" in
    rust) step "lint $dir (clippy)";        ( require_tools cargo && cd "$dir" && cargo clippy --all-targets -- -D warnings -D clippy::cognitive_complexity ) || rc=1 ;;
    go)   step "lint $dir (golangci-lint)"; ( require_tools go golangci-lint && cd "$dir" && golangci-lint run ./... ) || rc=1 ;;
  esac
done
(( rc == 0 )) || { err "gate lint RED"; exit 1; }
# The closing line says what ran: an empty run says so in its own words, never "green".
if (( ran == 0 )); then warn "nothing was linted — no selected target had a file to lint"
else ok "gate lint green — $ran target(s)"; fi
