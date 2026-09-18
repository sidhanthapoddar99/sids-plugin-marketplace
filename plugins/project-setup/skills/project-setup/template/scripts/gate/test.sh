#!/usr/bin/env bash
# gate/test.sh — `ctl gate test`. Rung 5: every app's own suite — unit, and integration once the
# engines exist. Layer and import rules are lint config, not tests; they run under `gate lint`.
# One implementation, two callers: it runs scripts/test/test.sh, the same worker `ctl test` runs.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage test "run every app's test suite as a gate" \
"It takes no arguments. Narrow a run while you work with \`ctl test [app]\`. The browser suite is
its own rung (\`ctl gate e2e\`): a browser bolted onto the fast gate makes agents stop running it." \
"Integration tests run against the real engine services in base; start them with \`ctl dev\`."; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate test" "use \`ctl test [app]\` to narrow a run" "$@"

gate_require_file "scripts/test/test.sh" "the test worker"
exec bash "$CTL_ROOT/scripts/test/test.sh"
