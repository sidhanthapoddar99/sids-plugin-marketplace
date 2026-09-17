#!/usr/bin/env bash
# Shared Linux/WSL lock primitive. Inherited descriptors keep the lock alive.
controller_lock_acquire() {
  exec {CONTROLLER_LOCK_FD}> "$1" || return 1
  if ! flock -n "$CONTROLLER_LOCK_FD"; then
    exec {CONTROLLER_LOCK_FD}>&-
    return 1
  fi
}

controller_lock_release() { exec {CONTROLLER_LOCK_FD}>&-; }

# A TypeScript coordinator can hold this helper open over stdin. EOF, including
# parent death, releases the lock. Metadata is diagnostic, never the lock itself.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  [[ ${1:-} == hold && $# == 4 ]] || { echo 'Usage: controller-lock hold LOCK_FILE OWNER_DIRECTORY OWNER_PID' >&2; exit 2; }
  lock_file=$2 owner_dir=$3 owner_pid=$4
  [[ $owner_pid =~ ^[1-9][0-9]*$ ]] || exit 2
  command -v jq >/dev/null || { echo 'Controller metadata requires jq' >&2; exit 1; }
  mkdir -p -- "$(dirname -- "$lock_file")"
  controller_lock_acquire "$lock_file" || { echo 'A controller is already running for this checkout; reuse it or run ctl stop.' >&2; exit 1; }
  process_birth() {
    local raw fields
    [[ -e /proc/$1/stat ]] || return 0
    read -r raw < "/proc/$1/stat" || return 1
    raw=${raw##*) }; read -ra fields <<< "$raw"
    [[ ${fields[0]} == Z ]] || printf '%s' "${fields[19]}"
  }
  if [[ -e $owner_dir/owner.json ]]; then
    prior_pid=$(jq -er '.pid | select(type == "number" and . > 0 and floor == .)' "$owner_dir/owner.json")
    prior_birth=$(jq -er 'if .birth == null then "" else .birth | select(type == "string" and test("^[0-9]+$")) end' "$owner_dir/owner.json")
    current_birth=$(process_birth "$prior_pid")
    if [[ -n $current_birth && ( -z $prior_birth || $prior_birth == "$current_birth" ) ]]; then
      echo 'Recorded controller is still running; refusing to replace it.' >&2
      exit 1
    fi
    echo 'Recovered an abandoned controller lock.' >&2
  fi
  birth=$(process_birth "$owner_pid")
  [[ -n $birth ]] || { echo 'Controller owner has already exited.' >&2; exit 1; }
  rm -rf -- "$owner_dir"
  mkdir -- "$owner_dir"
  printf '{"pid":%s,"birth":"%s"}\n' "$owner_pid" "$birth" > "$owner_dir/owner.json"
  trap 'rm -rf -- "$owner_dir"; controller_lock_release' EXIT
  printf 'locked\n'
  cat >/dev/null
fi
