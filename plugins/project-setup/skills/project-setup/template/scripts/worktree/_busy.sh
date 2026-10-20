#!/usr/bin/env bash
# scripts/worktree/_busy.sh — does anything ctl started in a slot still run? SOURCE it after _env.sh.
# create and remove refuse a busy slot, because switching a branch under a running stack, dev loop or
# gate breaks it. trim (by hand or weekly) skips a slot whose processes or gate still run, because
# deleting build outputs under them breaks them. The three callers share slot_busy, and it judges
# each kind of thing by ctl's own records:
#   processes   a process recorded under the slot's LOGS_DIR/run that may still run: the records
#               ctl dev and ctl build start write and ctl stop reads. process_live_records judges
#               them, as it does for ctl dev db stop, and a record it cannot verify counts too.
#   the gate    a gate that waits or runs in the slot: it holds ctl-gate.lock in the slot's git
#               folder (_slot_gate_reason). For a branch whose scripts predate that file, the gate
#               lock that the slot's scripts/gate/_lock.sh names (GATE_LOCK_FILE), held by a run in
#               this slot. It is tested with a shared flock that never waits and never writes. A lock
#               file inside the slot belongs to the slot. A lock that every checkout shares names its
#               holder on a checkout= line, and a held one without that line counts as busy, because
#               ctl cannot tell whose it is.
#   containers  running containers of the slot's compose project: its .env's COMPOSE_PROJECT_NAME,
#               else its folder name as compose reads it. When docker_state says missing or stopped,
#               no container can run. Any other Docker failure counts as busy, because ctl cannot tell.
#               The trim leaves containers out: they run from images and read no build output, and
#               the data core outlives ctl dev on purpose.

# slot_busy <slot folder> [builds] — print each thing still running there, one per line, and return 0
# when there is any; 1 when the slot is idle. With builds, only processes and the gate count.
slot_busy() {
  local reasons
  reasons=$(_slot_busy_reasons "$1" "${2:-}")
  [[ -n $reasons ]] || return 1
  printf '%s\n' "$reasons"
}

# The slot's .env is read in a subshell, so the caller's environment stays as it was. The slot's own
# keys replace any the caller has, because load_env_file never overwrites a variable that is set.
_slot_busy_reasons() (
  slot=$1 scope=$2
  cd -- "$slot" 2>/dev/null || { echo "its folder $slot cannot be opened"; exit 0; }
  CTL_ROOT=$slot
  unset COMPOSE_PROJECT_NAME "${WT_STORAGE_KEYS[@]}"
  if [[ -f .env ]]; then while IFS= read -r key; do unset "$key" 2>/dev/null || true; done < <(env_keys .env); fi
  load_env_file .env
  if expand_env_refs >/dev/null 2>&1 && resolve_storage_dirs >/dev/null 2>&1; then
    process_live_records || true
  else
    echo "its .env does not resolve LOGS_DIR, so ctl cannot tell whether a process it recorded still runs"
  fi
  _slot_gate_reason "$slot"
  [[ $scope != builds ]] || exit 0
  case $(docker_state) in missing|stopped) exit 0 ;; esac
  project=${COMPOSE_PROJECT_NAME:-$(wt_compose_name "${slot##*/}")}
  if ! ids=$(timeout 10 docker ps -q --filter "label=com.docker.compose.project=$project" 2>/dev/null); then
    echo "Docker did not answer, so ctl cannot tell whether containers of compose project $project run"
  elif [[ -n $ids ]]; then
    echo "$(wc -l <<< "$ids" | tr -d ' ') container(s) of compose project $project run"
  fi
)

# _slot_gate_reason <slot folder> — print a reason when a gate run waits or runs in the slot. A gate
# holds ctl-gate.lock in the slot's git folder from before its wait to its end, so an exclusive
# flock that never waits fails while one is there. A branch whose scripts predate that file is
# judged by the user's gate lock, which only a running gate holds.
_slot_gate_reason() {
  local slot=$1 file fd holder own
  if own=$(git -C "$slot" rev-parse --absolute-git-dir 2>/dev/null) && [[ -e $own/ctl-gate.lock ]]; then
    if ! { exec {fd}<"$own/ctl-gate.lock"; } 2>/dev/null; then
      echo "its gate lock $own/ctl-gate.lock cannot be opened, so ctl cannot tell whether a gate runs there"; return 0
    fi
    if ! flock -n -x "$fd"; then exec {fd}<&-; echo "a gate run waits or runs there: $own/ctl-gate.lock is held"; return 0; fi
    exec {fd}<&-
  fi
  [[ -f $slot/scripts/gate/_lock.sh ]] || return 0
  if ! file=$(source "$slot/scripts/gate/_lock.sh" >/dev/null 2>&1; printf '%s' "${GATE_LOCK_FILE-}"); then
    echo "its scripts/gate/_lock.sh does not load, so ctl cannot tell whether a gate runs there"; return 0
  fi
  [[ -n $file && -e $file ]] || return 0
  if ! { exec {fd}<"$file"; } 2>/dev/null; then
    echo "the gate lock $file cannot be opened, so ctl cannot tell whether a gate runs there"; return 0
  fi
  if flock -n -s "$fd"; then exec {fd}<&-; return 0; fi
  exec {fd}<&-
  holder=$(sed -n 's/^checkout=//p' "$file" 2>/dev/null | head -n 1)
  if [[ $file == "$slot"/* || -z $holder || $holder == "$slot" ]]; then
    echo "a gate run holds the gate lock: ${file#"$slot"/}${holder:+ (checkout $holder)}"
  fi
  return 0
}
