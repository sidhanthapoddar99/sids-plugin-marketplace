#!/usr/bin/env bash
# test/gate.sh — `ctl gate`. The ladder: lint → check → test → build, in the order that fails
# cheapest first, stopping at the first red and NAMING every rung it did not reach — so a
# partial run can never read as a full one. Runs through ctl because a repo without CI has
# nowhere else to run it; with CI, CI calls this.
#
#   -q / --quiet   capture each rung; print its counts when GREEN, its whole output when RED.
#                  Quiet hides nothing that failed — a quiet run and a loud run agree on every red.
#
# TODO (from neurasutra-editor scripts/gate/_lock.sh): one heavy run at a time via a lock file,
# and a memory lid via `systemd-run --user -p MemoryMax`. Port it when two concurrent gate runs
# become a real risk on the box that runs this.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] rung name → the command it runs. Order = the ladder.
RUNGS=(lint check test build)
rung_cmd() { case "$1" in
  lint)  echo "scripts/dev/lint.sh" ;;
  check) echo "scripts/config/check.sh" ;;
  test)  echo "scripts/test/test.sh" ;;
  build) echo "scripts/container/build.sh" ;;
esac; }
# the count lines worth keeping when a rung passed (pytest / bun / cargo / go shapes)
GATE_COUNTS='[0-9]+ (passed|failed|pass|fail|skip)|test result:|^(ok|FAIL)[[:space:]]|(✓|✗) '

usage() { print_help "gate" "the ladder: ${RUNGS[*]} — stop at the first red" \
  'gate [rung] [-q] [-h]' \
"Arguments
  rung            run one rung only: ${RUNGS[*]}

Options
  -q, --quiet     one line per GREEN rung with its counts; a RED rung prints in full
  -h, --help      show this help

The run stops at the first red rung and names every rung it did not reach." \
"A gate that cannot find its worker fails by name. It never reports green for work it did not run."; }

quiet=0 only=""
while (( $# )); do case "$1" in
  -q|--quiet) quiet=1; shift ;;
  -h|--help)  usage; exit 0 ;;
  -*)         die "unknown flag $1 (see ctl gate -h)" ;;
  *)          printf '%s\n' "${RUNGS[@]}" | grep -qx "$1" || die "unknown rung '$1' — one of: ${RUNGS[*]}"; only="$1"; shift ;;
esac; done
ladder=("${RUNGS[@]}"); [[ -n $only ]] && ladder=("$only")

for i in "${!ladder[@]}"; do
  rung="${ladder[$i]}"; worker="$(rung_cmd "$rung")"
  [[ -f $worker ]] || die "the worker for '$rung' not found: $worker — this rung has no target to run"
  section "gate $rung  (rung $(( i + 1 )) of ${#ladder[@]})"
  rc=0; started=$SECONDS
  if (( quiet )); then
    log="$(mktemp -t gate-XXXXXX)"
    bash "$worker" >"$log" 2>&1 || rc=$?
    if (( rc != 0 )); then cat "$log"; else grep -E "$GATE_COUNTS" "$log" | sed 's/^/  /' || true; fi
    rm -f "$log"
  else
    bash "$worker" || rc=$?
  fi
  took=$(( SECONDS - started ))
  if (( rc != 0 )); then
    err "gate $rung is RED (exit $rc) — the ladder stops here"
    skipped=("${ladder[@]:$(( i + 1 ))}")
    (( ${#skipped[@]} )) && err "NOT RUN, so nothing is known about them: ${skipped[*]}"
    exit "$rc"
  fi
  ok "gate $rung green — ${took}s"
done
hr
ok "gate green — ${ladder[*]} — ${SECONDS}s total"
