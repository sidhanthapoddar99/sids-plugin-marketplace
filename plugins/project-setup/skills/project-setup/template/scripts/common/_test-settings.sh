#!/usr/bin/env bash
# scripts/common/_test-settings.sh — the TESTING settings that `ctl gate`, its rungs and `ctl test`
# share. SOURCE it after _lib.sh. One copy, so the gate and the test runner cannot drift.
#
# THE SETTINGS, in the TESTING section of the root .env:
#   TEST_CPUS        the cores a run may use, as `taskset -c` reads them (0-7, 0-3,8-11).
#                    Empty: every core this shell may use.
#   TEST_MEMORY      the memory budget of a run (8G, 512M): the size of the gate's memory lid, and
#                    what an empty TEST_BUILD_JOBS divides. Empty: 80 % of the memory available
#                    when the run starts.
#   TEST_BUILD_JOBS  compiler jobs per Cargo command, handed to Cargo as CARGO_BUILD_JOBS.
#                    Empty: one per core the run may use, but no more than one per 2 GiB of the
#                    memory budget, and at least one.
#
# PRECEDENCE, highest first: the `ctl gate` flag (--cpus, --memory, --build-jobs), the process
# environment, the root .env, the default. For compiler jobs, a CARGO_BUILD_JOBS already set in the
# shell sits between --build-jobs and TEST_BUILD_JOBS. A CARGO_BUILD_JOBS line in .env is not read
# here, because .env names this budget TEST_BUILD_JOBS. An empty value keeps the default.
#
# WHY THE JOB DEFAULT LOOKS AT MEMORY. Cargo's own default is one job per core, and a rustc job on a
# debug build of a large workspace peaks near 1.3 GiB. A laptop with 8 cores and 6 GB free would run
# out of memory at Cargo's default. 2 GiB a job leaves room for the linker and for the tests that
# share the lid. A machine with more memory than cores gets one job per core, as Cargo would.
#
# A NESTED RUN AGREES. Each value is exported once it is resolved, and the root .env is loaded
# skip-if-set, so a run started from this one (the gate's test rung runs scripts/test/test.sh)
# resolves the same values, a flag's included. The settings line prints once per run.
#
# Bash builtins and /proc only, apart from taskset when TEST_CPUS is set, so a worker started with
# a minimal PATH can still read its settings.

TEST_JOB_MIB=2048       # the memory one compiler job may take when TEST_BUILD_JOBS is empty
TEST_MEMORY_SHARE=80    # the share of available memory an empty TEST_MEMORY gives a run
TEST_MEMORY_MIN_MIB=64  # a smaller budget cannot hold a compiler, so it is refused

# test_settings_init [cpus] [build-jobs] [memory] — the start of `ctl test` and of a rung run by
# name: load, check and apply the settings, and print what the run uses. Each argument is a flag's
# value, empty when the flag was not given. The gate runs these steps itself, around its lock.
test_settings_init() {
  test_settings_load
  test_settings_resolve "${1:-}" "${2:-}" "${3:-}"
  test_cpus_apply
  test_jobs_apply
  test_settings_line
}

# test_settings_load — load the root .env before any TEST_* value is read. The shell's own
# CARGO_BUILD_JOBS is kept first, because only a value from the shell outranks TEST_BUILD_JOBS.
test_settings_load() {
  _TS_SHELL_JOBS="${CARGO_BUILD_JOBS:-}"
  load_env_files
  expand_env_refs || die "the root .env holds a \${NAME} that does not resolve (named above)"
}

# test_size_mib <size> <where it came from> — "8G", "512M", "8GB" or a bare number (GB) in MiB.
# Anything else, or less than TEST_MEMORY_MIN_MIB, is refused naming the flag or key it came from.
test_size_mib() {
  local size="${1^^}" from="$2" mib=""
  size="${size%B}"
  case "$size" in
    *G) [[ ${size%G} =~ ^[0-9]{1,6}$ ]] && mib=$(( 10#${size%G} * 1024 )) ;;
    *M) [[ ${size%M} =~ ^[0-9]{1,9}$ ]] && mib=$(( 10#${size%M} )) ;;
    *)  [[ $size =~ ^[0-9]{1,6}$ ]] && mib=$(( 10#$size * 1024 )) ;;
  esac
  [[ -n $mib ]] || die "$from wants a size like 8G or 512M (got: $1)"
  (( mib >= TEST_MEMORY_MIN_MIB )) || die "$from wants at least ${TEST_MEMORY_MIN_MIB}M (got: $1)"
  printf '%s\n' "$mib"
}

# test_human <MiB> — "12 GB" or "512 MB"
test_human() { if (( $1 >= 1024 )); then printf '%s GB\n' "$(( $1 / 1024 ))"; else printf '%s MB\n' "$1"; fi; }

# test_settings_resolve <cpus-flag> <jobs-flag> <memory-flag> — check each value and export it under
# its own name. *_FROM names where each came from, for the messages. An empty flag was not given.
test_settings_resolve() {
  local cpus="$1" jobs="$2" memory="$3" range
  if [[ -n $cpus ]]; then TEST_CPUS_FROM=--cpus; else cpus="${TEST_CPUS:-}"; TEST_CPUS_FROM=TEST_CPUS; fi
  if [[ -n $cpus ]]; then
    [[ $cpus =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] \
      || die "$TEST_CPUS_FROM wants cores as taskset -c reads them, such as 0-7 or 0-3,8-11 (got: $cpus)"
    for range in ${cpus//,/ }; do
      [[ $range != *-* ]] || (( 10#${range%-*} <= 10#${range#*-} )) || die "$TEST_CPUS_FROM has a backwards range: $range"
    done
  fi
  export TEST_CPUS="$cpus"

  if [[ -n $memory ]]; then TEST_MEMORY_FROM=--memory; else memory="${TEST_MEMORY:-}"; TEST_MEMORY_FROM=TEST_MEMORY; fi
  [[ -z $memory ]] || test_size_mib "$memory" "$TEST_MEMORY_FROM" >/dev/null
  export TEST_MEMORY="$memory"

  if [[ -n $jobs ]]; then TEST_BUILD_JOBS_FROM=--build-jobs
  elif [[ -n ${_TS_SHELL_JOBS:-} ]]; then jobs="$_TS_SHELL_JOBS"; TEST_BUILD_JOBS_FROM="CARGO_BUILD_JOBS in the shell"
  else jobs="${TEST_BUILD_JOBS:-}"; TEST_BUILD_JOBS_FROM=TEST_BUILD_JOBS; fi
  [[ -z $jobs || $jobs =~ ^[1-9][0-9]{0,3}$ ]] \
    || die "${TEST_BUILD_JOBS_FROM%% *} wants a whole number of compiler jobs from 1 to 9999 (got: $jobs)"
  export TEST_BUILD_JOBS="$jobs"
}

# test_core_count <list> — how many cores a taskset -c list names
test_core_count() {
  local part count=0 IFS=,
  for part in $1; do
    if [[ $part == *-* ]]; then count=$(( count + 10#${part#*-} - 10#${part%-*} + 1 )); else count=$(( count + 1 )); fi
  done
  printf '%s\n' "$count"
}

# test_allowed_cores — the cores this shell may run on now, as the kernel lists them
test_allowed_cores() {
  local key value
  while IFS=$' \t' read -r key value; do
    [[ $key == Cpus_allowed_list: ]] && { printf '%s\n' "$value"; return 0; }
  done < "/proc/$BASHPID/status"
  return 1
}

# test_cpus_apply — bind this shell, and so every process it starts, to TEST_CPUS. A core the
# machine cannot give is an error, never a quietly smaller run.
test_cpus_apply() {
  [[ -n ${TEST_CPUS:-} ]] || return 0
  command -v taskset >/dev/null 2>&1 || die "$TEST_CPUS_FROM needs taskset (util-linux) to bind the run to its cores"
  taskset -c -p "$TEST_CPUS" "$BASHPID" >/dev/null 2>&1 || die "this machine cannot run on cores $TEST_CPUS ($TEST_CPUS_FROM)"
  local want got
  want=$(test_core_count "$TEST_CPUS"); got=$(test_core_count "$(test_allowed_cores)")
  (( got == want )) \
    || die "this machine gives $got of the $want cores in $TEST_CPUS ($TEST_CPUS_FROM); name each core once, and only cores it has"
}

# test_available_mib — MemAvailable from /proc/meminfo, in MiB
test_available_mib() {
  local key value _
  while read -r key value _; do [[ $key == MemAvailable: ]] && { printf '%s\n' "$(( value / 1024 ))"; return 0; }; done < /proc/meminfo
  return 1
}

# test_memory_budget_mib — the memory budget of this run in MiB: TEST_MEMORY when it is set, else
# TEST_MEMORY_SHARE % of the memory available now. The gate's lid and the job default both use it.
test_memory_budget_mib() {
  if [[ -n ${TEST_MEMORY:-} ]]; then test_size_mib "$TEST_MEMORY" "${TEST_MEMORY_FROM:-TEST_MEMORY}"; return; fi
  local available budget
  available=$(test_available_mib) || die "cannot read MemAvailable in /proc/meminfo — set TEST_MEMORY, such as 8G"
  budget=$(( available * TEST_MEMORY_SHARE / 100 ))
  (( budget >= TEST_MEMORY_MIN_MIB )) || die "only $(test_human "$available") of memory is available — too little for a test run"
  printf '%s\n' "$budget"
}

# test_memory_budget_words — how the budget was chosen, for the messages
test_memory_budget_words() {
  if [[ -n ${TEST_MEMORY:-} ]]; then printf '%s %s\n' "${TEST_MEMORY_FROM:-TEST_MEMORY}" "$TEST_MEMORY"
  else printf '%s %% of %s available\n' "$TEST_MEMORY_SHARE" "$(test_human "$(test_available_mib)")"; fi
}

# test_jobs_apply — export CARGO_BUILD_JOBS: TEST_BUILD_JOBS when resolved, else the default from
# the cores this run may use and its memory budget. Run it after test_cpus_apply, which sets the cores.
test_jobs_apply() {
  local cores budget jobs
  if [[ -n ${TEST_BUILD_JOBS:-} ]]; then
    jobs="$TEST_BUILD_JOBS"; TEST_JOBS_WORDS="$TEST_BUILD_JOBS_FROM"
  else
    cores=$(test_core_count "$(test_allowed_cores)")
    budget=$(test_memory_budget_mib) || exit 1
    jobs=$(( budget / TEST_JOB_MIB ))
    (( jobs <= cores )) || jobs=$cores
    (( jobs >= 1 )) || jobs=1
    TEST_JOBS_WORDS="the default, from $cores cores and a memory budget of $(test_human "$budget") at 2 GB a job"
  fi
  export CARGO_BUILD_JOBS="$jobs"
}

# test_settings_line — one line that says what this run uses, printed once: a nested run skips it
test_settings_line() {
  [[ -z ${CTL_TEST_SETTINGS_SHOWN:-} ]] || return 0
  export CTL_TEST_SETTINGS_SHOWN=1
  local allowed where
  allowed=$(test_allowed_cores)
  if [[ -n ${TEST_CPUS:-} ]]; then where="$TEST_CPUS_FROM"; else where="every core"; fi
  say "· cores $allowed ($(test_core_count "$allowed"), $where) · $CARGO_BUILD_JOBS compiler job(s) per Cargo command ($TEST_JOBS_WORDS)"
}
