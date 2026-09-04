#!/usr/bin/env bash
# gate/check.sh — `ctl gate check`. Rung 6: the repo-level conformance floor — env contract,
# layout, compose validity, the brief. It runs scripts/config/check.sh, the same worker `ctl check`
# runs. App-level structure checks are tests and ran under `gate test`; this rung holds only what
# no test runner can express (shell over the whole repo and docker compose config).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage check "the repo conformance floor as a gate (env · layout · compose · brief)" \
"It takes no arguments. \`ctl check\` runs the same worker directly."; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate check" "run \`ctl check\` directly" "$@"

gate_require_file "scripts/config/check.sh" "the check worker"
exec bash "$CTL_ROOT/scripts/config/check.sh"
