#!/usr/bin/env bash
# gate/all.sh — `ctl gate`. THE LADDER, in the order that fails cheapest first:
#
#   lint → typecheck → dead → audit → test → check → build → e2e
#
# Stop at the first red and NAME every rung not reached, so a partial run never reads as a full
# one. `--quiet` keeps counts per rung and prints a red rung in full.
#
# WHAT RUNS. Three modes, one at a time (scripts/gate/_changed.sh selects):
#   changed  the default, also `--changed`: the rungs and targets the uncommitted changes reach.
#   delta    `--delta <base>`: the same, for the changes from a branch, a commit or a date-time.
#   all      `--all`, or `all` as a word: every rung on every target, only when truly required.
# lint, typecheck and test narrow to the targets the changes reach. check always runs in full, and
# the other rungs run in full whenever anything changed. A path no rule maps widens the run to every
# target. `--dry-run` prints the change set and what it selects, and runs nothing. The closing line
# names what ran and what the changes did not reach.
#
# ONE RUN PER TREE. A green run records the tree it checked (_receipt.sh). A run on a tree that
# already passed with the same base prints so and runs nothing, in every checkout of the repository;
# `--rerun` runs it again.
#
# SETTINGS. The TESTING section of the root .env sets the cores, the compiler jobs and the memory
# budget (scripts/common/_test-settings.sh); --cpus, --build-jobs and --memory win over it. The root
# .env is loaded before any of them is read. One gate run per user at a time, under one memory lid
# (_lock.sh); a second run waits.
#
# `ctl gate static` runs the static rungs of RUNGS (read the code), `ctl gate dynamic` the dynamic
# ones (run the code). Both keep the ladder order, in any mode.
#
# [ADAPT] RUNGS. The floor is `lint typecheck test check`: seconds each, no extra tooling. A rung
# joins when the user says so and the project earns it (a dead-code cleanup → `dead`; the first
# external user → `audit`; an image → `build`; a user flow → `e2e`) and leaves the same way. Which rungs
# the ladder holds is written in AGENTS.md; keep the two lists equal. `clones`, `fuzz`, `perf` run BY
# NAME (`ctl gate clones`), never here: a rung that reports zero every run is a rung people stop reading.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"
source "$CTL_ROOT/scripts/common/_test-settings.sh"
source "$CTL_ROOT/scripts/gate/_lock.sh"
source "$CTL_ROOT/scripts/gate/_targets.sh"
source "$CTL_ROOT/scripts/gate/_changed.sh"
source "$CTL_ROOT/scripts/gate/_receipt.sh"

LADDER=(lint typecheck dead audit test check build e2e)   # the full order. Never edited.
RUNGS=(lint typecheck test check)                          # [ADAPT] the rungs this repo runs, a subset of LADDER
DYNAMIC=(test e2e)                                         # rungs that run the code; the rest are static
TARGETED=(lint typecheck test)                             # rungs a changed-only run narrows to targets (_targets.sh)

usage() { print_help "gate" "the ladder: ${RUNGS[*]} — stop at the first red" \
  'gate [static|dynamic] [--changed | --delta <base> | --all] [--dry-run] [--rerun] [-q] [--cpus LIST] [--build-jobs N] [--memory SIZE] [-h]
  ctl gate <rung> [args] [-q]' \
"What runs  (one mode at a time; check always runs)
  --changed                            the default: the rungs and targets the uncommitted changes reach
                                       (the diff against HEAD, plus untracked files). ctl, scripts/, the
                                       toolchain file, apps/packages/, root config and any unmapped path
                                       reach everything
  --delta <base>                       the same, for the changes from <base> to the working tree. <base> is
                                       a branch, a commit, or a local date-time: YYYY-MM-DD or
                                       YYYY-MM-DD HH:MM[:SS] (a date means the last commit before it began)
  --all, all                           every listed rung on every target, only when truly required
  --dry-run                            with the default, --changed or --delta: print every changed path and
                                       what it selects, run nothing
  --rerun                              run even when a green run on this tree with the same base is recorded

The ladder, in order  (ctl gate runs the rungs this repo lists; ctl gate <rung> runs one)
  lint [app…] [--staged]               ruff · clippy · oxlint · gofmt  (--staged: staged files only, the pre-commit hook)
  typecheck [app…]                     tsc --noEmit · mypy · cargo check · go vet
  dead                                 dead-code census at zero: knip full + production · deptry · cargo udeps
  audit                                gitleaks · bandit · pip-audit · bun audit · cargo audit · govulncheck
  test                                 every app's own suite  (= ctl test)
  check                                the repo contract: env · layout · compose · brief  (= ctl check)
  build                                every image and bundle, plus the Go binary  (= ctl build)
  e2e                                  the whole browser suite on a throwaway stack  (= ctl test e2e)

Groups  (the listed rungs, filtered by kind, ladder order kept, in any mode)
  static                               the rungs that read the code: lint typecheck dead audit check build
  dynamic                              the rungs that run the code: test e2e

By name  (never in the ladder: a rung reporting zero every run stops being read)
  clones [--all] [--max N] [--report]  copy-pasted code, jscpd over apps/
  fuzz [--time S]                      hypothesis · fast-check · cargo fuzz targets
  perf                                 pytest-benchmark · k6 · cargo bench → logs/perf/

Options  (a flag wins over the shell, the shell over the TESTING section of .env, .env over the default)
  -q, --quiet                          one line per GREEN rung with its counts; a RED rung still prints in full
  --cpus LIST                          the cores this run may use, as taskset -c reads them (0-7, 0-3,8-11).
                                       Else TEST_CPUS; default: every core this shell may use
  --build-jobs N                       compiler jobs per Cargo command. Else CARGO_BUILD_JOBS from the shell,
                                       then TEST_BUILD_JOBS; default: one per core, at most one per 2 GB of
                                       the memory budget
  --memory SIZE                        the memory budget and lid of this run (8G, 512M). Else TEST_MEMORY;
                                       default: 80 % of what is available
  -h, --help                           show this help

A green run records the tree it checked. A run on a tree that already passed, with the same base and
group, says so and runs nothing, in every checkout of this repository.

AGENTS.md names the ladder this repo runs (RUNGS in this file). The run stops at the first red rung and
names every rung it did not reach. One gate run per user at a time: a second run waits for the first.
Each rung has its own help: ctl gate <rung> -h." \
"A gate that cannot find its target fails by name. It never reports green for work it did not run."; }

# flag_value <flag> <value> — a flag that takes a value must get one
flag_value() { [[ -n ${2:-} && ${2:-} != -* ]] || die "$1 needs a value (see ctl gate --help)"; }

INNER=0; [[ -z ${GATE_LID:-} ]] || INNER=1   # the half of a lidded run that runs inside the lid
QUIET=0 CPUS_FLAG="" JOBS_FLAG="" MEMORY_FLAG="" FULL=0 CHANGED_FLAG=0 DELTA_FLAG=0 DELTA_BASE="" DRY_RUN=0 RERUN=0 GROUP=all
ORIG_ARGS=("$@") rest=()
while (( $# )); do case "$1" in
  -q|--quiet)     QUIET=1 ;;
  --cpus)         flag_value "$1" "${2:-}"; CPUS_FLAG="$2"; shift ;;
  --cpus=*)       CPUS_FLAG="${1#*=}"; flag_value --cpus "$CPUS_FLAG" ;;
  --build-jobs)   flag_value "$1" "${2:-}"; JOBS_FLAG="$2"; shift ;;
  --build-jobs=*) JOBS_FLAG="${1#*=}"; flag_value --build-jobs "$JOBS_FLAG" ;;
  --memory)       flag_value "$1" "${2:-}"; MEMORY_FLAG="$2"; shift ;;
  --memory=*)     MEMORY_FLAG="${1#*=}"; flag_value --memory "$MEMORY_FLAG" ;;
  # --changed takes no value: a word after it that is no group was meant as a base.
  --changed)      CHANGED_FLAG=1
                  if [[ -n ${2:-} && $2 != -* && $2 != all && $2 != static && $2 != dynamic ]]; then
                    die "--changed takes no base; for changes since $2, use --delta $2"; fi ;;
  --changed=*)    die "--changed takes no base; for changes since ${1#*=}, use --delta ${1#*=}" ;;
  --delta)        flag_value "$1" "${2:-}"; DELTA_FLAG=1 DELTA_BASE="$2"; shift ;;
  --delta=*)      DELTA_FLAG=1 DELTA_BASE="${1#*=}"; flag_value --delta "$DELTA_BASE" ;;
  --all|all)      FULL=1 ;;
  --dry-run)      DRY_RUN=1 ;;
  --rerun)        RERUN=1 ;;
  static|dynamic) GROUP="$1" ;;
  *)              rest+=("$1") ;;
esac; shift; done
set -- ${rest[@]+"${rest[@]}"}
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate $GROUP" "run one rung with \`ctl gate <rung>\`" "$@"
(( FULL + CHANGED_FLAG + DELTA_FLAG <= 1 )) || die "--changed, --delta and --all each choose what runs; give one of them"
(( ! (FULL && DRY_RUN) )) || die "--dry-run shows what a changed-only run selects; --all selects every rung and target"

# RUNGS must be a subset of LADDER, in ladder order; a typo here must not read as a green rung.
is_dynamic()  { local r; for r in "${DYNAMIC[@]}"; do [[ $r == "$1" ]] && return 0; done; return 1; }
is_targeted() { local r; for r in "${TARGETED[@]}"; do [[ $r == "$1" ]] && return 0; done; return 1; }
SELECTED=()
for rung in "${LADDER[@]}"; do
  for r in "${RUNGS[@]}"; do [[ $r == "$rung" ]] || continue
    case "$GROUP" in
      all)     SELECTED+=("$rung") ;;
      static)  is_dynamic "$rung" || SELECTED+=("$rung") ;;
      dynamic) is_dynamic "$rung" && SELECTED+=("$rung") ;;
    esac
  done
done
for r in "${RUNGS[@]}"; do
  found=0; for rung in "${LADDER[@]}"; do [[ $r == "$rung" ]] && found=1; done
  (( found )) || die "RUNGS names '$r', which is not a ladder rung (${LADDER[*]})"
done
# The floor is not optional: a RUNGS without it would run a green gate over unlinted, untyped or
# untested code, and nothing downstream could tell. `ctl check` compares RUNGS with AGENTS.md too.
FLOOR=(lint typecheck test check)
for f in "${FLOOR[@]}"; do
  found=0; for r in "${RUNGS[@]}"; do [[ $r == "$f" ]] && found=1; done
  (( found )) || die "RUNGS omits '$f' — the floor is ${FLOOR[*]}"
done
(( ${#SELECTED[@]} )) || die "no $GROUP rung is listed in RUNGS (${RUNGS[*]}) — nothing to prove"
RUNGS=("${SELECTED[@]}")

# rung_targets <rung> — the reached targets that are rows of <rung> with a folder on disk, in table
# order. A deleted app's paths still count as changed, but there is nothing left to check there.
rung_targets() {
  local name folder _ out=""
  while read -r name folder _; do
    [[ " $CHANGED_TARGETS " == *" $name "* && -d $CTL_ROOT/$folder ]] && out+=" $name"
  done < <(gate_target_rows "$1")
  printf '%s\n' "${out# }"
}

# plan_rungs [quiet] — what each rung runs: "full", a list of targets, or "" when the changes do not
# reach it. Without `quiet` it prints the change set and the plan.
declare -A RUNG_PLAN=()
CHANGED_FULL=0 CHANGED_COUNT=0 CHANGED_TARGETS="" CHANGED_SCOPE="" CHANGED_NONE="" CHANGED_WHY=""
plan_rungs() {
  local quiet="${1:-}" rung words list=""
  (( ! DRY_RUN )) || list=all
  gate_reaches_check
  if (( ! FULL )); then
    if [[ -n $quiet ]]; then gate_changed_select "$DELTA_BASE" >/dev/null; else gate_changed_select "$DELTA_BASE" "$list"; fi
  fi
  for rung in "${RUNGS[@]}"; do
    if (( FULL || CHANGED_FULL )) || [[ $rung == check ]]; then RUNG_PLAN[$rung]=full
    elif is_targeted "$rung"; then RUNG_PLAN[$rung]=$(rung_targets "$rung")
    elif (( CHANGED_COUNT )); then RUNG_PLAN[$rung]=full
    else RUNG_PLAN[$rung]=""; fi
    (( ! FULL )) && [[ -z $quiet ]] || continue
    case "${RUNG_PLAN[$rung]}" in
      full) if [[ $rung == check ]]; then words="runs (always)"
            elif is_targeted "$rung"; then words="every target"
            else words="runs in full"; fi ;;
      "")   words="not reached — skipped" ;;
      *)    words="${RUNG_PLAN[$rung]}" ;;
    esac
    say "  $rung: $words"
  done
}

# skipped_parts — each rung, or rung and targets, the plan leaves out, as "lint (app docs)" or "test"
skipped_parts() {
  local rung name folder _ plan others
  for rung in "${RUNGS[@]}"; do
    plan=${RUNG_PLAN[$rung]}
    case $plan in
      full) ;;
      "")   printf '%s\n' "$rung" ;;
      *)    others=""
            while read -r name folder _; do
              [[ -d $CTL_ROOT/$folder && " $plan " != *" $name "* ]] && others+=" $name"
            done < <(gate_target_rows "$rung")
            [[ -z $others ]] || printf '%s (%s)\n' "$rung" "${others# }" ;;
    esac
  done
}

if (( DRY_RUN )); then plan_rungs; exit 0; fi

# Settings come before the lock, so a bad value fails at once and a waiting run says what it will use.
test_settings_load
test_settings_resolve "$CPUS_FLAG" "$JOBS_FLAG" "$MEMORY_FLAG"
test_cpus_apply
test_jobs_apply

# The plan comes before the lock too, so a bad --delta base fails at once. The half inside the lid
# works it out again, quietly, because it is a new process.
if (( INNER )); then plan_rungs quiet; else plan_rungs; fi
test_settings_line

# A tree that already passed with the same base needs no second run. The key is taken now, so files
# edited during the run cannot be recorded as checked.
RECEIPT=0
if gate_receipt_key "$FULL" "${CHANGED_BASE:-}"; then
  RECEIPT=1
  if (( ! RERUN && ! INNER )) && receipt=$(gate_receipt_find "$GROUP"); then
    ok "gate $GROUP: already green on this tree — $(<"$receipt") — nothing ran; --rerun runs it again"
    exit 0
  fi
fi

gate_lock_take "gate $GROUP" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
gate_lid_reexec "${BASH_SOURCE[0]}" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

# run_rung <rung> — the rung's worker in full, or on its targets. The test rung's targets go to
# scripts/test/test.sh, the worker the rung itself runs, because the rung takes no target.
run_rung() {
  local rung="$1" targets=()
  if [[ ${RUNG_PLAN[$rung]} == full ]]; then bash "$CTL_ROOT/scripts/gate/$rung.sh"; return; fi
  read -r -a targets <<< "${RUNG_PLAN[$rung]}"
  if [[ $rung == test ]]; then bash "$CTL_ROOT/scripts/test/test.sh" "${targets[@]}"
  else bash "$CTL_ROOT/scripts/gate/$rung.sh" "${targets[@]}"; fi
}

ran=()
for i in "${!RUNGS[@]}"; do
  rung="${RUNGS[$i]}"; worker="scripts/gate/$rung.sh"
  [[ -n ${RUNG_PLAN[$rung]} ]] || continue
  gate_require_file "$worker" "the gate worker for '$rung'"
  gate_lock_step "$rung"
  label=""; [[ ${RUNG_PLAN[$rung]} == full ]] || label=" — ${RUNG_PLAN[$rung]}"
  section "gate $rung  (rung $(( i + 1 )) of ${#RUNGS[@]})$label"
  rc=0; started=$SECONDS
  if (( QUIET )); then
    log="$(mktemp -t gate-XXXXXX)"
    run_rung "$rung" >"$log" 2>&1 || rc=$?
    gate_report_capture "$log" "$rc"; rm -f "$log"
  else
    run_rung "$rung" || rc=$?
  fi
  took=$(( SECONDS - started ))
  if (( rc != 0 )); then
    err "gate $rung is RED (exit $rc) — the ladder stops here"
    left=("${RUNGS[@]:$(( i + 1 ))}")
    (( ${#left[@]} )) && err "NOT RUN, so nothing is known about them: ${left[*]}"
    mapfile -t skipped < <(skipped_parts)
    (( ${#skipped[@]} )) && err "skipped before the run, not reached by the changes: ${skipped[*]}"
    exit "$rc"
  fi
  ok "gate $rung green — ${took}s"
  ran+=("$rung${label:+ (${RUNG_PLAN[$rung]})}")
done
hr
# Record the run only when the tree is still the one it checked.
if (( RECEIPT )) && [[ $(gate_work_tree 2>/dev/null) == "$GATE_RECEIPT_TREE" ]]; then
  gate_receipt_write "$GROUP" "${SECONDS}s" || warn "could not record this green run in $(gate_receipt_dir)"
fi
mapfile -t skipped < <(skipped_parts)
if (( FULL )); then
  ok "gate --all green — every target of ${RUNGS[*]} — ${SECONDS}s total"
elif (( CHANGED_FULL )); then
  ok "gate green — ${CHANGED_WHY}, so the selection widened to every target of ${RUNGS[*]} — ${SECONDS}s total"
elif (( ${#ran[@]} == 0 )); then
  ok "nothing to run — ${CHANGED_COUNT} changed path(s), and they reach no ${GROUP} rung · skipped, not reached by the changes: ${skipped[*]} — ${SECONDS}s total"
elif (( CHANGED_COUNT == 0 )); then
  ok "gate green — ${CHANGED_NONE} — ran ${ran[*]} only — ${SECONDS}s total"
else
  ok "gate green for ${CHANGED_SCOPE} only, a PARTIAL run — ran: ${ran[*]} · skipped, not reached by the changes: ${skipped[*]:-none} — ${SECONDS}s total"
fi
