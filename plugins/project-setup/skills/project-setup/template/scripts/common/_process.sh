#!/usr/bin/env bash

PROCESS_RECORDS=()
PROCESS_PENDING=""

process_identity() {
  local stat
  [[ $1 =~ ^[0-9]+$ && -r /proc/$1/stat ]] || return 1
  read -r stat < "/proc/$1/stat" || return 1
  stat="${stat##*) }"
  local fields=(); read -ra fields <<< "$stat"
  printf '%s\n' "${fields[19]}"
}

process_valid() {
  local pid birth
  [[ -f $1/pid ]] || return 1
  read -r pid birth < "$1/pid" || return 1
  [[ -n $birth && $(process_identity "$pid") == "$birth" ]]
}

process_stop() (
  local record="$1" pid birth process_lock
  exec {process_lock}> "$record.lock"
  flock -w 2 "$process_lock" || return 1
  if process_valid "$record"; then
    read -r pid birth < "$record/pid"
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 0.3
    process_valid "$record" && kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$record"
)

process_cleanup() {
  local record attempt
  if [[ -n ${process_lock:-} ]]; then exec {process_lock}>&-; fi
  if [[ -n $PROCESS_PENDING ]]; then
    for attempt in {1..20}; do
      [[ -f $PROCESS_PENDING/pid ]] && break
      sleep 0.05
    done
  fi
  for record in "${PROCESS_RECORDS[@]}"; do process_stop "$record" || true; done
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
  PROCESS_RECORDS+=("$PROCESS_RECORD")
  PROCESS_PENDING="$PROCESS_RECORD"
  setsid bash -c '
    record=$1; directory=$2; shift 2
    trap ":" TERM INT HUP
    stat=$(cat /proc/$$/stat); stat=${stat##*) }; read -ra fields <<< "$stat"
    printf "%s %s\n" "$$" "${fields[19]}" > "$record/pid"
    for attempt in {1..100}; do
      [[ -f $record/go ]] && break
      sleep 0.05
    done
    if [[ -f $record/go ]]; then
      cd -- "$directory" || exit 1
      env --default-signal=INT,TERM,HUP "$@" & child=$!
      wait "$child"; result=$?
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
  local record
  for record in "${PROCESS_RECORDS[@]}"; do process_status "$record" || return $?; done
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
