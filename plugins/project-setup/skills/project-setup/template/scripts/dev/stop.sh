#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help stop "Stop this project's managed host processes, then containers; keep data." \
  'stop [--dry-run] [-h]' \
  $'Options\n  --dry-run    list owned targets without stopping or cleaning records\n  -h, --help   show this help\n\nStops recorded dev groups, watchers and frozen servers before Docker services.\nUnrecorded port listeners are never killed. Containers and volumes are retained.\nFailures return nonzero; unresolved writers prevent database shutdown.'; }

dry=0
for argument in "$@"; do
  case "$argument" in
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $argument (try ctl stop --help)" ;;
  esac
done

load_env_files
expand_env_refs || exit 1
resolve_storage_dirs || exit 1
result=0
for record in "$LOGS_DIR"/run/*.process; do
  [[ -e $record || -L $record ]] || continue
  if (( dry )); then
    if [[ ! -L $record ]] && process_owned "$record" "$CTL_ROOT"; then
      say "would stop or clean record: ${record##*/}"
    else
      err "cannot establish project ownership: $record"; result=1
    fi
  elif process_stop "$record" "$CTL_ROOT"; then
    ok "stopped or cleaned: ${record##*/}"
  else
    err "could not stop: ${record##*/}"; result=1
  fi
done
for record in "$LOGS_DIR"/run/*.pid; do
  [[ -e $record || -L $record ]] || continue
  if [[ -L $record || ! -f $record ]]; then
    err "unsafe legacy record: $record"; result=1
  elif read -r pid < "$record" && [[ -n $(process_identity "$pid") ]]; then
    err "live PID-only record needs manual ownership verification: $record"; result=1
  elif (( dry )); then
    say "would clean stale legacy record: ${record##*/}"
  else
    rm -- "$record" || result=1
  fi
done
(( result == 0 )) || die "host shutdown incomplete; containers left running to protect data"

command -v docker >/dev/null 2>&1 || die "host cleanup complete; Docker is not installed"
command -v timeout >/dev/null 2>&1 || die "host cleanup complete; timeout is required to check Docker"
command -v jq >/dev/null 2>&1 || die "host cleanup complete; jq is required to identify the Compose project"
timeout --kill-after=2 10 docker info >/dev/null 2>&1 || die "host cleanup complete; Docker is unreachable"
mapfile -t compose < <(compose_argv -f "$BASE")
project=$(timeout --kill-after=2 15 "${compose[@]}" config --format json | jq -er '.name | select(type == "string" and length > 0)') \
  || die "host cleanup complete; cannot resolve the Compose project"
containers=$(timeout --kill-after=2 10 docker ps --all \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.project.working_dir=$CTL_ROOT" \
  --format '{{.ID}} {{.Label "com.docker.compose.service"}}') \
  || die "host cleanup complete; cannot list project containers"

writers=() databases=()
while read -r identifier service; do
  [[ -n $identifier ]] || continue
  [[ $identifier =~ ^[a-f0-9]+$ && -n $service ]] || die "invalid Compose container identity"
  is_data=0
  for data_service in "${DATA_SVCS[@]}"; do [[ $service != "$data_service" ]] || is_data=1; done
  if (( is_data )); then databases+=("$identifier"); else writers+=("$identifier"); fi
  (( ! dry )) || say "would stop container: $service ($identifier)"
done <<< "$containers"
(( ! dry )) || exit 0

stop_containers() {
  local identifier state failed=0
  for identifier in "$@"; do
    timeout --kill-after=2 20 docker stop --time 10 "$identifier" >/dev/null || failed=1
    state=$(timeout --kill-after=2 10 docker inspect \
      --format '{{.State.Running}} {{.State.Restarting}} {{.State.Paused}}' "$identifier") || { failed=1; continue; }
    [[ $state == 'false false false' ]] || failed=1
  done
  return "$failed"
}

stop_containers "${writers[@]}" || die "container writers did not stop; databases left running"
stop_containers "${databases[@]}" || die "some database containers did not stop"
ok "project stopped; containers, data and volumes preserved"
