#!/usr/bin/env bash
# gate/typecheck.sh — `ctl gate typecheck [app]`. Rung 2: static types per app (tsc --noEmit · mypy · cargo check · go vet).
# One implementation, two callers: the ladder runs it with no arguments (the whole repo); by name it
# takes a target. -q/--quiet is the shared gate capture.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"
gate_quiet_reexec "$@"

usage() { print_help "gate typecheck" "Typecheck every app (tsc · mypy · cargo check · go vet)." \
  'gate typecheck [api|engine|landing|app|single|docs|dashboard|cli] [-h]' \
"Arguments
  (none)          every app
  api             uv run mypy app
  engine          cargo check --workspace --all-targets
  landing, app, single, docs, dashboard   bun run typecheck  (tsc --noEmit, or next typegen + tsc)
  cli             go vet ./...

Options
  -q, --quiet     counts only when green; a red run prints in full
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
target="${1:-all}"; rc=0
tc_py() { [[ -d $1 ]] || return 0; step "typecheck $1 (mypy)";        ( cd "$1" && uv run mypy app ) || rc=1; }
tc_rs() { [[ -d $1 ]] || return 0; step "typecheck $1 (cargo check)"; ( cd "$1" && cargo check --workspace --all-targets ) || rc=1; }
tc_js() { [[ -d $1 ]] || return 0; step "typecheck $1 (tsc)";         ( cd "$1" && bun run typecheck ) || rc=1; }
tc_go() { [[ -d $1 ]] || return 0; step "typecheck $1 (go vet)";      ( cd "$1" && go vet ./... ) || rc=1; }
case "$target" in
  all)      tc_py apps/example-api-python; tc_rs apps/example-engine-rust; tc_js apps/example-multi-web-app/landing; tc_js apps/example-multi-web-app/app; tc_js apps/example-multi-web-app/docs; tc_js apps/example-single-web-app-vite; tc_js apps/example-dashboard-nextjs; tc_go apps/example-tui-go ;;
  api)      tc_py apps/example-api-python ;;
  engine)   tc_rs apps/example-engine-rust ;;
  landing)  tc_js apps/example-multi-web-app/landing ;;
  app)      tc_js apps/example-multi-web-app/app ;;
  single)   tc_js apps/example-single-web-app-vite ;;
  docs)     tc_js apps/example-multi-web-app/docs ;;
  dashboard) tc_js apps/example-dashboard-nextjs ;;
  cli)      tc_go apps/example-tui-go ;;
  *)        die "unknown target: $target (all|api|engine|landing|app|single|docs|dashboard|cli)" ;;
esac
(( rc == 0 )) && ok "gate typecheck green" || err "gate typecheck RED"
exit $rc
