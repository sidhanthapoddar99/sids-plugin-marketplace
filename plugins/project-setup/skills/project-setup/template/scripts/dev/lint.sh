#!/usr/bin/env bash
# dev/lint.sh — `ctl lint [app] [--staged]`. Lint every app with its own tool (non-mutating,
# CI-friendly). --staged limits the run to git-staged files, for the pre-commit hook.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "lint" "Lint every app (non-mutating)." \
  'lint [api|engine|web|site|cli|database] [--staged] [-h]' \
"Arguments
  (none)          lint everything
  api, database   ruff check
  engine          cargo fmt --check + clippy -D warnings
  web, site       bun run lint  (oxlint)
  cli             gofmt -l + go vet

Options
  --staged        only git-staged files (skips an app with no staged file under it)
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target=all staged=0
while (( $# )); do case "$1" in
  --staged) staged=1; shift ;;
  -*)       die "unknown flag $1 (see ctl lint -h)" ;;
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
  all)      lint_py apps/api; lint_py apps/database/postgres; lint_rs apps/engine; lint_js apps/web; lint_js apps/site; lint_go apps/cli ;;
  api)      lint_py apps/api ;;
  database) lint_py apps/database/postgres ;;
  engine)   lint_rs apps/engine ;;
  web)      lint_js apps/web ;;
  site)     lint_js apps/site ;;
  cli)      lint_go apps/cli ;;
  *)        die "unknown target: $target (all|api|engine|web|site|cli|database)" ;;
esac
(( rc == 0 )) && ok "lint clean" || err "lint issues"
exit $rc
