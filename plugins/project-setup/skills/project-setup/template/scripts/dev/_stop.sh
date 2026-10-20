#!/usr/bin/env bash
# dev/_stop.sh — stop this project's recorded host processes and its containers. Shared by
# `ctl stop`, `ctl dev stop` and `ctl dev db stop`. Sourced after _lib.sh, with the env loaded and
# storage resolved. Ownership comes from process records with start identities and from the
# Compose project labels, never from whatever listens on a port.

# stop_host_processes <dry> — stop or clean every record under LOGS_DIR/run. Returns 1 when a record
# cannot be verified or a group does not stop, so the caller leaves the databases running under it.
stop_host_processes() {
  local dry=$1 record pid result=0
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
  return "$result"
}

# project_containers — this project's containers, one "<id> <service> <plane> <state>" line each.
# plane is data for a DATA_SVCS service and apps for everything else. A container belongs to the
# project only when both its Compose project label and its working-directory label match, which
# also catches orphans left by another stack shape of this project. Every Docker call is bounded.
project_containers() {
  local project listing identifier service state plane data_service
  command -v docker >/dev/null 2>&1 || { err "Docker is not installed"; return 1; }
  command -v timeout >/dev/null 2>&1 || { err "timeout is required to check Docker"; return 1; }
  command -v jq >/dev/null 2>&1 || { err "jq is required to identify the Compose project"; return 1; }
  timeout --kill-after=2 10 docker info >/dev/null 2>&1 || { err "Docker is unreachable"; return 1; }
  local -a compose=()
  mapfile -t compose < <(compose_argv -f "$BASE")
  project=$(timeout --kill-after=2 15 "${compose[@]}" config --format json | jq -er '.name | select(type == "string" and length > 0)') \
    || { err "cannot resolve the Compose project"; return 1; }
  listing=$(timeout --kill-after=2 10 docker ps --all \
    --filter "label=com.docker.compose.project=$project" \
    --filter "label=com.docker.compose.project.working_dir=$CTL_ROOT" \
    --format '{{.ID}} {{.Label "com.docker.compose.service"}} {{.State}}') \
    || { err "cannot list project containers"; return 1; }
  while read -r identifier service state; do
    [[ -n $identifier ]] || continue
    [[ $identifier =~ ^[a-f0-9]+$ && -n $service && -n $state ]] || { err "invalid Compose container identity"; return 1; }
    plane=apps
    for data_service in "${DATA_SVCS[@]}"; do [[ $service != "$data_service" ]] || plane=data; done
    printf '%s %s %s %s\n' "$identifier" "$service" "$plane" "$state"
  done <<< "$listing"
}

# stop_container_ids <id…> — docker stop each, then prove it is no longer running.
stop_container_ids() {
  local identifier state failed=0
  for identifier in "$@"; do
    timeout --kill-after=2 20 docker stop --time 10 "$identifier" >/dev/null || failed=1
    state=$(timeout --kill-after=2 10 docker inspect \
      --format '{{.State.Running}} {{.State.Restarting}} {{.State.Paused}}' "$identifier") || { failed=1; continue; }
    [[ $state == 'false false false' ]] || failed=1
  done
  return "$failed"
}

# stop_containers <dry> <plane…> — stop this project's containers in the named planes (apps, data),
# apps first, so a database never stops under a writer. A writer that fails to stop leaves the
# databases running. Stopping only the data plane is refused while an app container runs.
# `docker stop` keeps containers, networks and volumes, so the next start reuses them.
stop_containers() {
  local dry=$1 listing identifier service plane state; shift
  local planes=" $* "
  local -a writers=() databases=() live_writers=()
  listing=$(project_containers) || return 1
  while read -r identifier service plane state; do
    [[ -n $identifier ]] || continue
    if [[ $plane == apps ]]; then
      case "$state" in exited|created|dead) ;; *) live_writers+=("$service") ;; esac
    fi
    [[ $planes == *" $plane "* ]] || continue
    if [[ $plane == data ]]; then databases+=("$identifier"); else writers+=("$identifier"); fi
    (( ! dry )) || say "would stop container: $service ($identifier)"
  done <<< "$listing"
  if [[ $planes == *" data "* && $planes != *" apps "* ]] && (( ${#live_writers[@]} )); then
    err "app containers still run on the data core: ${live_writers[*]} — stop everything with ctl stop"
    return 1
  fi
  (( ! dry )) || return 0
  stop_container_ids "${writers[@]}" || { err "container writers did not stop; databases left running"; return 1; }
  stop_container_ids "${databases[@]}" || { err "some database containers did not stop"; return 1; }
}
