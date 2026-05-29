#!/usr/bin/env bash
# dev-lint.sh — `ctl lint`. Lint backend + frontend (non-mutating; CI-friendly).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "lint" "Lint backend + frontend (non-mutating)." \
  'lint [backend|frontend] [-h]' \
"Arguments
  (none)          lint both
  backend         ruff check (apps/backend)
  frontend        biome/eslint (apps/frontend)

Options
  -h, --help      show this help" \
"Stack-specific — adapt the tools below (ruff/biome) to your project, or drop this worker."; }

is_help "${1:-}" && { usage; exit 0; }
target="${1:-all}"; rc=0
lint_be() { [[ -d apps/backend ]] || return 0; step "lint backend (ruff)";   ( cd apps/backend  && uv run ruff check . ) || rc=1; }
lint_fe() { [[ -d apps/frontend ]] || return 0; step "lint frontend (biome)"; ( cd apps/frontend && bunx @biomejs/biome lint . ) || rc=1; }
case "$target" in
  all)      lint_be; lint_fe ;;
  backend)  lint_be ;;
  frontend) lint_fe ;;
  *)        die "unknown target: $target (all|backend|frontend)" ;;
esac
(( rc == 0 )) && ok "lint clean" || err "lint issues"
exit $rc
