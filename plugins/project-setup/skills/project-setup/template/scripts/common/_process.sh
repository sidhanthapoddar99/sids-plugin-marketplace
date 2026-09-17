#!/usr/bin/env bash

PROCESS_RECORDS=()
PROCESS_PENDING=""
declare -A PROCESS_OWNERS=()

process_identity() {
  local stat
  [[ $1 =~ ^[0-9]+$ && -r /proc/$1/stat ]] || return 1
  read -r stat < "/proc/$1/stat" || return 1
  stat="${stat##*) }"
  local fields=(); read -ra fields <<< "$stat"
  printf '%s\n' "${fields[19]}"
}

process_running() {
  local pid birth stat fields
  [[ -f $1/pid ]] || return 1
  read -r pid birth < "$1/pid" || return 1
  [[ -n $birth && $(process_identity "$pid") == "$birth" ]] || return 1
  read -r stat < "/proc/$pid/stat" || return 1
  stat="${stat##*) }"; read -ra fields <<< "$stat"
  [[ ${fields[0]} != Z ]]
}

process_valid() {
  local pid birth stat fields
  process_running "$1" || return 1
  read -r pid birth < "$1/pid" || return 1
  read -r stat < "/proc/$pid/stat" || return 1
  stat="${stat##*) }"; read -ra fields <<< "$stat"
  [[ ${fields[2]} == "$pid" && ${fields[3]} == "$pid" ]]
}

process_group_members() {
  local group="$1" entry stat fields
  for entry in /proc/[0-9]*/stat; do
    { read -r stat < "$entry"; } 2>/dev/null || continue
    stat="${stat##*) }"; read -ra fields <<< "$stat"
    [[ ${fields[0]} != Z && ${fields[2]} == "$group" && ${fields[3]} == "$group" ]] || continue
    entry=${entry%/stat}
    printf '%s %s\n' "${entry##*/}" "${fields[19]}"
  done
}

process_owned() {
  local record="$1" root="$2" owner pid birth directory
  if [[ -f $record/project ]]; then
    read -r owner < "$record/project" || return 1
    [[ $owner == "$root" ]]
  elif process_valid "$record"; then
    read -r pid birth < "$record/pid"
    directory=$(readlink "/proc/$pid/cwd") || return 1
    [[ $directory == "$root" || $directory == "$root/"* ]]
  else
    return 0
  fi
}

process_stop() (
  local record="$1" pid birth process_lock member identity attempt active deadline
  local grace="${PROCESS_STOP_TIMEOUT:-20}"
  local -a members=()
  [[ -e $record || -L $record ]] || return 0
  [[ -d $record && ! -L $record ]] || return 1
  exec {process_lock}> "$record.lock" || return 1
  flock -w 2 "$process_lock" || return 1
  if [[ ${3+x} ]]; then
    [[ -n $3 && -f $record/pid ]] || return 1
    read -r pid birth < "$record/pid" || return 1
    [[ "$pid $birth" == "$3" ]] || return 0
  fi
  [[ $grace =~ ^[1-9][0-9]*$ ]] || return 1
  if [[ -n ${2:-} ]] && ! process_owned "$record" "$2"; then
    printf 'cannot establish project ownership: %s\n' "$record" >&2
    return 1
  fi
  if process_valid "$record"; then
    read -r pid birth < "$record/pid"
    mapfile -t members < <(process_group_members "$pid")
    [[ " ${members[*]} " == *" $pid $birth "* ]] || return 1
    process_valid "$record" || return 1
    kill -TERM -- "-$pid" 2>/dev/null || return 1
    deadline=$((SECONDS + grace))
    while (( SECONDS < deadline )); do
      [[ -n $(process_group_members "$pid") ]] || break
      sleep 0.1
    done
    for member in "${members[@]}"; do
      read -r member identity <<< "$member"
      if [[ $(process_identity "$member") == "$identity" ]] &&
         [[ $'\n'$(process_group_members "$pid")$'\n' == *$'\n'"$member $identity"$'\n'* ]]; then
        kill -KILL -- "-$pid" 2>/dev/null || return 1
        break
      fi
    done
    for attempt in {1..20}; do
      active=$(process_group_members "$pid")
      [[ -z $active ]] && break
      sleep 0.05
    done
    [[ -z $active ]] || { printf 'process group did not stop: %s\n' "$record" >&2; return 1; }
    wait "$pid" 2>/dev/null || true
  elif [[ -f $record/pid ]]; then
    read -r pid birth < "$record/pid" || true
    if [[ -n $(process_identity "${pid:-}") && -z ${birth:-} ]]; then
      printf 'live PID without a start identity: %s\n' "$record" >&2
      return 1
    fi
    if process_running "$record" ||
       [[ -n ${birth:-} && $(process_identity "${pid:-}") == "$birth" &&
          -n $(process_group_members "$pid") ]]; then
      printf 'unverifiable live process group: %s\n' "$record" >&2
      return 1
    fi
  fi
  rm -rf -- "$record"
)

process_cleanup() {
  local record attempt pid birth
  if [[ -n ${process_lock:-} ]]; then exec {process_lock}>&-; fi
  if [[ -n $PROCESS_PENDING ]]; then
    for attempt in {1..20}; do
      [[ -f $PROCESS_PENDING/pid ]] && break
      sleep 0.05
    done
    if read -r pid birth < "$PROCESS_PENDING/pid"; then
      PROCESS_OWNERS["$PROCESS_PENDING"]="$pid $birth"
    fi
  fi
  for record in "${PROCESS_RECORDS[@]}"; do
    process_stop "$record" "" "${PROCESS_OWNERS[$record]:-}" || true
  done
}

process_init() {
  require_tools setsid flock timeout env sleep
  [[ -r /proc/self/stat ]] || die "host lifecycle requires Linux /proc and GNU coreutils"
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'process_cleanup' EXIT
}

process_start() {
  local name="$1" directory="$2" process_lock pid birth; shift 2
  [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid process name: $name"
  resolve_storage_dirs || return
  mkdir -p -- "$LOGS_DIR/run" "$LOGS_DIR/dev"
  PROCESS_RECORD="$LOGS_DIR/run/$name.process"
  exec {process_lock}> "$PROCESS_RECORD.lock"
  if ! flock -w 2 "$process_lock"; then exec {process_lock}>&-; return 1; fi
  if [[ -d $PROCESS_RECORD ]]; then
    if [[ -f $PROCESS_RECORD/pid ]] && read -r pid birth < "$PROCESS_RECORD/pid" &&
       [[ $pid =~ ^[0-9]+$ && $birth =~ ^[0-9]+$ ]] && ! process_valid "$PROCESS_RECORD"; then
      rm -rf -- "$PROCESS_RECORD"
    else
      exec {process_lock}>&-
      printf 'live or incomplete process record: %s\n' "$PROCESS_RECORD" >&2
      return 1
    fi
  fi
  mkdir -- "$PROCESS_RECORD" || { printf 'process record already exists: %s\n' "$PROCESS_RECORD" >&2; return 1; }
  printf '%s\n' "$CTL_ROOT" > "$PROCESS_RECORD/project"
  PROCESS_RECORDS+=("$PROCESS_RECORD")
  PROCESS_PENDING="$PROCESS_RECORD"
  setsid bash -c '
    record=$1; directory=$2; shift 2
    stopping=0
    trap "stopping=1" TERM INT HUP
    stat=$(cat /proc/$$/stat); stat=${stat##*) }; read -ra fields <<< "$stat"
    printf "%s %s\n" "$$" "${fields[19]}" > "$record/pid"
    for attempt in {1..100}; do
      [[ -f $record/go || $stopping == 1 ]] && break
      sleep 0.05
    done
    if [[ -f $record/go && $stopping == 0 ]]; then
      cd -- "$directory" || exit 1
      env --default-signal=INT,TERM,HUP "$@" & child=$!
      (( stopping == 0 )) || kill -TERM "$child" 2>/dev/null
      while :; do
        wait "$child"; result=$?
        kill -0 "$child" 2>/dev/null || break
      done
      printf "%s\n" "$result" > "$record/status.tmp"
      mv -- "$record/status.tmp" "$record/status"
    fi
    kill -KILL -- -$$
  ' bash "$PROCESS_RECORD" "$directory" "$@" {process_lock}>&- < /dev/null >> "$LOGS_DIR/dev/$name.log" 2>&1 &
  local attempt
  for attempt in {1..20}; do
    [[ -s $PROCESS_RECORD/pid ]] && break
    sleep 0.05
  done
  if ! process_valid "$PROCESS_RECORD"; then exec {process_lock}>&-; return 1; fi
  read -r pid birth < "$PROCESS_RECORD/pid"
  PROCESS_OWNERS["$PROCESS_RECORD"]="$pid $birth"
  PROCESS_PENDING=""
  touch "$PROCESS_RECORD/go"
  exec {process_lock}>&-
}

process_status() {
  local result
  if [[ -f $1/status ]]; then
    read -r result < "$1/status"
    [[ $result =~ ^[0-9]+$ ]] || result=1
    (( result != 0 )) || result=1
    return "$result"
  fi
  process_valid "$1"
}

process_check_all() {
  local record pid birth
  for record in "${PROCESS_RECORDS[@]}"; do
    read -r pid birth < "$record/pid" || return 1
    [[ "$pid $birth" == "${PROCESS_OWNERS[$record]:-}" ]] || return 1
    process_status "$record" || return $?
  done
}

process_ready() {
  local seconds="$1" probe="$2" deadline
  [[ $seconds =~ ^[1-9][0-9]*$ ]] || { printf 'readiness timeout must be positive seconds\n' >&2; return 1; }
  deadline=$((SECONDS + seconds))
  while (( SECONDS < deadline )); do
    process_check_all || return $?
    if timeout --kill-after=1 1 bash -c "$probe" >/dev/null 2>&1; then
      process_check_all; return $?
    fi
    sleep 0.1
  done
  printf 'readiness timed out after %ss\n' "$seconds" >&2
  return 124
}

process_monitor() {
  while :; do process_check_all || return $?; sleep 0.1; done
}

process_release() {
  PROCESS_RECORDS=()
  PROCESS_PENDING=""
  PROCESS_OWNERS=()
}

process_for_pid() {
  local listener="$1" record pid birth group
  group=$(ps -o pgid= -p "$listener" 2>/dev/null); group=${group// /}
  for record in "$LOGS_DIR"/run/*.process; do
    process_valid "$record" || continue
    read -r pid birth < "$record/pid"
    [[ $pid == "$group" ]] && { printf '%s\n' "$record"; return 0; }
  done
  return 1
}
