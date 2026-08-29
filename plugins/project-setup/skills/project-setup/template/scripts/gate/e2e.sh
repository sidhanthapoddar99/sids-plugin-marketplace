#!/usr/bin/env bash
# gate/e2e.sh — `ctl gate e2e`. Rung 8, last: the whole browser suite against a built stack on a
# throwaway DATA_DIR. It runs scripts/test/e2e.sh and nothing else — one implementation of the
# browser suite, two callers (`ctl test e2e` and this rung). Last because it is the most expensive
# rung by a wide margin; in the ladder because a rung outside it runs only when somebody remembers.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage e2e "the whole browser suite as the ladder's last rung" \
"It takes no arguments. To keep the stack up after a red run, use \`ctl test e2e --keep\`." \
"The stack is \`ctl up +expose\` on a fresh mktemp DATA_DIR; data/ is never read or written."; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate e2e" "run the suite directly with \`ctl test e2e\`" "$@"

gate_require_file "scripts/test/e2e.sh" "the e2e worker"
exec bash "$CTL_ROOT/scripts/test/e2e.sh"
