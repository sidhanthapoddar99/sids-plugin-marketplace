#!/usr/bin/env bash
# gate/all.sh — `ctl gate [all]`. THE LADDER, in the order that fails cheapest first:
#
#   lint → typecheck → dead → audit → test → check → build → e2e
#   ├── must ──────────────────────────────┤  ├── recommended ─────┤
#
# Stop at the first red and NAME every rung not reached, so a partial run never reads as a full
# one. `--quiet` keeps counts per rung and prints a red rung in full. One heavy run at a time,
# under one memory lid (_lock.sh).
#
# [ADAPT] RUNGS. The four must rungs stay. A recommended rung joins when the project earns it
# (a database → integration inside `test`; a second app → `check` structure tests; an image →
# `build`; a user flow → `e2e`) and is never removed. Which rungs the ladder holds is written in
# AGENTS.md. `clones`, `fuzz`, `perf` run BY NAME (`ctl gate clones`), never here: a rung that
# reports zero every run is a rung people stop reading.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

RUNGS=(lint typecheck dead audit test check build e2e)

usage() { print_help "gate" "the ladder: ${RUNGS[*]} — stop at the first red" \
  'gate [all] [-q] [--memory SIZE] [-h]   ·   ctl gate <rung> [args] [-q]' \
"The ladder, in order  (ctl gate / ctl gate all runs every rung; ctl gate <rung> runs one)
  lint [app] [--staged]                ruff · clippy · oxlint · gofmt  (--staged: staged files only, the pre-commit hook)
  typecheck [app]                      tsc --noEmit · mypy · cargo check · go vet
  dead                                 dead-code census at zero: knip full + production · deptry · cargo udeps
  audit                                gitleaks · bandit · pip-audit · bun audit · cargo audit · govulncheck
  test                                 every app's own suite, structure tests among them  (= ctl test)
  check                                repo conformance floor: env contract · layout · compose · brief  (= ctl check)
  build                                every image and bundle, plus the Go binary  (= ctl build)
  e2e                                  the whole browser suite on a throwaway stack  (= ctl test e2e)

By name  (never in the ladder: a rung reporting zero every run stops being read)
  clones [--all] [--max N] [--report]  copy-pasted code, jscpd over apps/
  fuzz [--time S]                      hypothesis · fast-check · cargo fuzz targets
  perf                                 pytest-benchmark · k6 · cargo bench → logs/perf/

Options
  -q, --quiet                          one line per GREEN rung with its counts; a RED rung still prints in full
  --memory SIZE                        the memory lid for this run (4G, 512M). Default: 80 % of what is available
  -h, --help                           show this help

AGENTS.md names the ladder this repo runs. The run stops at the first red rung and names every rung it
did not reach. Each rung has its own help: ctl gate <rung> -h." \
"A gate that cannot find its target fails by name. It never reports green for work it did not run."; }

QUIET=0 GATE_MEMORY="" ORIG_ARGS=("$@") rest=()
while (( $# )); do case "$1" in
  -q|--quiet) QUIET=1 ;;
  --memory)   GATE_MEMORY="${2:-}"; shift ;;
  --memory=*) GATE_MEMORY="${1#--memory=}" ;;
  all)        ;;
  *)          rest+=("$1") ;;
esac; shift; done
set -- ${rest[@]+"${rest[@]}"}
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate all" "run one rung with \`ctl gate <rung>\`" "$@"

source "$CTL_ROOT/scripts/gate/_lock.sh"
gate_lock_take "gate all" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
gate_lid_reexec "${BASH_SOURCE[0]}" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

for i in "${!RUNGS[@]}"; do
  rung="${RUNGS[$i]}"; worker="scripts/gate/$rung.sh"
  gate_require_file "$worker" "the gate worker for '$rung'"
  gate_lock_step "$rung"
  section "gate $rung  (rung $(( i + 1 )) of ${#RUNGS[@]})"
  rc=0; started=$SECONDS
  if (( QUIET )); then
    log="$(mktemp -t gate-XXXXXX)"
    bash "$CTL_ROOT/$worker" >"$log" 2>&1 || rc=$?
    gate_report_capture "$log" "$rc"; rm -f "$log"
  else
    bash "$CTL_ROOT/$worker" || rc=$?
  fi
  took=$(( SECONDS - started ))
  if (( rc != 0 )); then
    err "gate $rung is RED (exit $rc) — the ladder stops here"
    skipped=("${RUNGS[@]:$(( i + 1 ))}")
    (( ${#skipped[@]} )) && err "NOT RUN, so nothing is known about them: ${skipped[*]}"
    exit "$rc"
  fi
  ok "gate $rung green — ${took}s"
done
hr
ok "gate green — ${RUNGS[*]} — ${SECONDS}s total"
