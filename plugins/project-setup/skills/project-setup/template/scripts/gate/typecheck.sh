#!/usr/bin/env bash
# gate/typecheck.sh — `ctl gate typecheck [target…]`. Rung 2: static types per app (tsc --noEmit · mypy · cargo check · go vet).
# One implementation, two callers: the ladder runs it with no target (the whole repo) or with the
# targets a changed-only run reaches; by name it takes targets. -q/--quiet is the shared gate
# capture. The apps are the rows of scripts/gate/_targets.sh.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"
source "$CTL_ROOT/scripts/gate/_targets.sh"
source "$CTL_ROOT/scripts/common/_test-settings.sh"
gate_quiet_reexec "$@"

usage() { print_help "gate typecheck" "Typecheck every app (tsc · mypy · cargo check · go vet)." \
  "gate typecheck [$(gate_target_names typecheck)]… [-h]" \
"Targets  (none: every target whose folder exists; scripts/gate/_targets.sh lists them)
$(gate_target_help typecheck)

What runs, per ecosystem
  python          uv run mypy app
  rust            cargo check --workspace --all-targets
  bun             bun run typecheck  (tsc --noEmit, or next typegen + tsc)
  go              go vet ./...

Options
  -q, --quiet     counts only when green; a red run prints in full
  -h, --help      show this help

Cores and compiler jobs come from the TESTING section of .env (ctl gate --help)."; }

is_help "${1:-}" && { usage; exit 0; }
names=()
while (( $# )); do case "$1" in
  -*) die "unknown flag $1 (see ctl gate typecheck -h)" ;;
  *)  names+=("$1") ;;
esac; shift; done
gate_target_select typecheck ${names[@]+"${names[@]}"}
test_settings_init
rc=0 ran=0
for row in ${GATE_SELECTED[@]+"${GATE_SELECTED[@]}"}; do
  read -r name dir ecosystem <<< "$row"
  case "$ecosystem" in
    python) step "typecheck $dir (mypy)";        ( require_tools uv && cd "$dir" && uv run mypy app ) || rc=1 ;;
    rust)   step "typecheck $dir (cargo check)"; ( require_tools cargo && cd "$dir" && cargo check --workspace --all-targets ) || rc=1 ;;
    bun)    step "typecheck $dir (tsc)";         ( require_tools bun && cd "$dir" && bun run typecheck ) || rc=1 ;;
    go)     step "typecheck $dir (go vet)";      ( require_tools go && cd "$dir" && go vet ./... ) || rc=1 ;;
    *)      die "scripts/gate/_targets.sh gives $name the ecosystem '$ecosystem'; typecheck knows python, rust, bun and go" ;;
  esac
  ran=$(( ran + 1 ))
done
(( rc == 0 )) || { err "gate typecheck RED"; exit 1; }
if (( ran == 0 )); then warn "nothing was typechecked — no target folder exists"
else ok "gate typecheck green — $ran target(s)"; fi
