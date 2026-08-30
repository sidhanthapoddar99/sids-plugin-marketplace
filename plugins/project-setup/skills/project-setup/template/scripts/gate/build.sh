#!/usr/bin/env bash
# gate/build.sh — `ctl gate build`. Rung 7: every image and bundle compiles. It runs
# scripts/container/build.sh (the same worker `ctl build` runs) with no target, so every service
# with a build: context is built, plus the Go binary when the repo has one.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage build "build every image and bundle as a gate" \
"It takes no arguments. Build one service while you work with \`ctl build <app>\`." \
"Needs docker. A missing engine fails by name, never as a build error."; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate build" "use \`ctl build <app>\` for one service" "$@"

gate_require_file "scripts/container/build.sh" "the build worker"
require_docker
bash "$CTL_ROOT/scripts/container/build.sh"
if compgen -G "apps/*/go.mod" >/dev/null; then bash "$CTL_ROOT/scripts/container/build.sh" cli; fi
