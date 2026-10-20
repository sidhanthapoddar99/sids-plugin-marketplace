#!/usr/bin/env bash
# scripts/worktree/_busy.sh — does anything ctl started in a slot still run? SOURCE it after _env.sh.
# create and remove refuse a busy slot, and trim (by hand or weekly) skips one, because switching a
# branch or deleting build outputs under a running stack, dev loop or gate breaks it. The three
# callers share slot_busy, and it judges each kind of thing by ctl's own records:
#   processes   a live process recorded under the slot's LOGS_DIR/run: the records ctl dev and
#               ctl build start write and ctl stop reads (process_running). A live PID-only record
#               counts too.
#   the gate    the gate lock that the slot's scripts/gate/_lock.sh names (GATE_LOCK_FILE), held by
#               a run in this slot. It is tested with a shared flock that never waits and never
#               writes. A lock file inside the slot belongs to the slot. A lock that every checkout
#               shares names its holder on a checkout= line, and a held one without that line counts
#               as busy, because ctl cannot tell whose it is.
#   containers  running containers of the slot's compose project: its .env's COMPOSE_PROJECT_NAME,
#               else its folder name as compose reads it. When docker_state says missing or stopped,
#               no container can run. Any other Docker failure counts as busy, because ctl cannot tell.

# slot_busy <slot folder> — print each thing still running there, one per line, and return 0 when
# there is any; 1 when the slot is idle
slot_busy() {
  local reasons
  reasons=$(_slot_busy_reasons "$1")
  [[ -n $reasons ]] || return 1
  printf '%s\n' "$reasons"
}

# The slot's .env is read in a subshell, so the caller's environment stays as it was. The slot's own
# keys replace any the caller has, because load_env_file never overwrites a variable that is set.
_slot_busy_reasons() (
  slot=$1
  cd -- "$slot" 2>/dev/null || { echo "its folder $slot cannot be opened"; exit 0; }
  CTL_ROOT=$slot
  unset COMPOSE_PROJECT_NAME "${WT_STORAGE_KEYS[@]}"
  if [[ -f .env ]]; then while IFS= read -r key; do unset "$key" 2>/dev/null || true; done < <(env_keys .env); fi
  load_env_file .env
  if expand_env_refs >/dev/null 2>&1 && resolve_storage_dirs >/dev/null 2>&1; then
    for record in "$LOGS_DIR"/run/*.process; do
      [[ -d $record && ! -L $record ]] && process_running "$record" && echo "a process ctl started still runs: ${record#"$slot"/}"
    done
    for record in "$LOGS_DIR"/run/*.pid; do
      [[ -f $record ]] && read -r pid < "$record" && [[ -n $(process_identity "$pid") ]] \
        && echo "a process with a PID-only record still runs: ${record#"$slot"/}"
    done
  else
    echo "its .env does not resolve LOGS_DIR, so ctl cannot tell whether a process it recorded still runs"
  fi
  _slot_gate_reason "$slot"
  case $(docker_state) in missing|stopped) exit 0 ;; esac
  project=${COMPOSE_PROJECT_NAME:-$(wt_compose_name "${slot##*/}")}
  if ! ids=$(timeout 10 docker ps -q --filter "label=com.docker.compose.project=$project" 2>/dev/null); then
    echo "Docker did not answer, so ctl cannot tell whether containers of compose project $project run"
  elif [[ -n $ids ]]; then
    echo "$(wc -l <<< "$ids" | tr -d ' ') container(s) of compose project $project run"
  fi
)

# _slot_gate_reason <slot folder> — print a reason when a gate run holds the gate lock for the slot
_slot_gate_reason() {
  local slot=$1 file fd holder
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
