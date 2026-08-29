#!/usr/bin/env bash
# gate/lint.sh — `ctl gate lint [app] [--staged]`. Rung 1: every linter over every app; first because it is the cheapest answer in the ladder.
# One implementation, two callers: the ladder runs it with no arguments (the whole repo); by name it
# takes a target and --staged (the pre-commit hook). -q/--quiet is the shared gate capture.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"
gate_quiet_reexec "$@"

usage() { print_help "gate lint" "Lint every app (non-mutating)." \
  'gate lint [api|engine|landing|app|docs|dashboard|cli|database] [--staged] [-h]' \
"Arguments
  (none)          lint everything
  api, database   ruff check
  engine          cargo fmt --check + clippy -D warnings
  landing, app, docs, dashboard   bun run lint  (oxlint)
  cli             gofmt -l + go vet

Options
  --staged        only git-staged files (skips an app with no staged file under it)
  -q, --quiet     counts only when green; a red run prints in full
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target=all staged=0
while (( $# )); do case "$1" in
  --staged) staged=1; shift ;;
  -*)       die "unknown flag $1 (see ctl gate lint -h)" ;;
  *)        target="$1"; shift ;;
esac; done
rc=0
# touched <dir> — with --staged: 0 only if a staged file lives under <dir>
touched() { (( staged )) || return 0; git diff --cached --name-only --diff-filter=ACMR -- "$1" | grep -q .; }
lint_py()   { [[ -d $1 ]] && touched "$1" || return 0; step "lint $1 (ruff)";         ( cd "$1" && uv run ruff check . ) || rc=1; }
lint_rs()   { [[ -d $1 ]] && touched "$1" || return 0; step "lint $1 (fmt + clippy)"; ( cd "$1" && cargo fmt --check && cargo clippy --all-targets -- -D warnings ) || rc=1; }
lint_js()   { [[ -d $1 ]] && touched "$1" || return 0; step "lint $1 (bun run lint)"; ( cd "$1" && bun run lint ) || rc=1; }
lint_go()   { [[ -d $1 ]] && touched "$1" || return 0; step "lint $1 (gofmt + vet)";  ( cd "$1" && test -z "$(gofmt -l .)" && go vet ./... ) || rc=1; }
case "$target" in
  all)      lint_py apps/example-api-python; lint_py apps/database/postgres; lint_rs apps/example-engine-rust; lint_js apps/example-multi-web-app/landing; lint_js apps/example-multi-web-app/app; lint_js apps/example-multi-web-app/docs; lint_js apps/example-dashboard-nextjs; lint_go apps/example-tui-go ;;
  api)      lint_py apps/example-api-python ;;
  database) lint_py apps/database/postgres ;;
  engine)   lint_rs apps/example-engine-rust ;;
  landing)  lint_js apps/example-multi-web-app/landing ;;
  app)      lint_js apps/example-multi-web-app/app ;;
  single)   lint_js apps/example-single-web-app-vite ;;
  docs)     lint_js apps/example-multi-web-app/docs ;;
  dashboard) lint_js apps/example-dashboard-nextjs ;;
  cli)      lint_go apps/example-tui-go ;;
  *)        die "unknown target: $target (all|api|engine|landing|app|docs|dashboard|cli|database)" ;;
esac
(( rc == 0 )) && ok "gate lint green" || err "gate lint RED"
exit $rc
