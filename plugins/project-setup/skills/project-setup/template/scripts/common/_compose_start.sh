#!/usr/bin/env bash

compose_start_call() {
  local remaining=$((start_deadline - SECONDS))
  (( remaining > 0 )) || { err "startup readiness timed out"; return 124; }
  timeout --kill-after=2 "${remaining}s" "$@"
}

compose_start_state() {
  local service="$1" required="$2" oneshot="$3" health="$4" replicas="$5" ids states result
  ids=$(compose_start_call "${compose_base[@]}" ps --all --quiet "$service") || return $?
  if [[ -z $ids ]]; then
    result=pending
  else
    local -a containers=()
    mapfile -t containers <<< "$ids"
    states=$(compose_start_call docker inspect --format '{{json .State}}' "${containers[@]}") || return $?
    result=$(jq -rs --argjson oneshot "$oneshot" --argjson health "$health" --argjson replicas "$replicas" '
      if length == 0 then "pending"
      elif any(.[]; .Status == "dead" or .Status == "removing"
        or (.Status == "exited" and ($oneshot | not))
        or (.Status == "exited" and .ExitCode != 0)
        or (.Health.Status == "unhealthy")) then "failed"
      elif length < $replicas then "pending"
      elif all(.[];
        if $oneshot then .Status == "exited" and .ExitCode == 0
        else .Status == "running" and
          (if $health or .Health != null then .Health.Status == "healthy" else true end)
        end) then "ready"
      else "pending" end' <<< "$states") || return $?
  fi
  if [[ $required == false ]]; then
    if [[ $result != ready && ! -v start_warned[$service] ]]; then
      warn "optional dependency $service is $result; it does not block readiness"
      start_warned[$service]=1
    fi
    return 0
  fi
  case "$result" in
    ready) return 0 ;;
    failed) err "$service failed readiness (exited, unhealthy, or failed one-shot)"; return 1 ;;
    *) start_pending+=("$service"); return 0 ;;
  esac
}

compose_start_check() {
  local service required oneshot health replicas
  start_pending=()
  while IFS=$'\t' read -r service required oneshot health replicas; do
    [[ -n $service ]] || continue
    compose_start_state "$service" "$required" "$oneshot" "$health" "$replicas" || return $?
  done <<< "$start_contract"
}

compose_start_interrupt() {
  local status="$1"
  trap '' INT TERM
  if [[ -n $start_child ]]; then
    kill -TERM "$start_child" 2>/dev/null || true
    wait "$start_child" 2>/dev/null || true
  fi
  if (( start_attach && start_activated )); then
    timeout --kill-after=2 10s "${compose_base[@]}" stop --timeout 5 "${start_services[@]}" || true
  fi
  exit "$status"
}

compose_start() (
  local start_attach="$1" start_timeout="$2"; shift 2
  local start_child='' start_activated=0 start_deadline model selected start_contract build_help status service
  local required oneshot health replicas start_long_running=0
  local -a start_services=() start_pending=()
  local -A start_warned=()
  [[ $start_attach =~ ^[01]$ && $start_timeout =~ ^[1-9][0-9]*$ ]] || {
    err "compose_start needs attach=0|1 and a positive readiness timeout"; return 1;
  }
  require_tools jq timeout || return $?
  resolve_storage_dirs || return
  trap 'compose_start_interrupt 130' INT
  trap 'compose_start_interrupt 143' TERM
  model=$("${compose_base[@]}" config --format json) || return $?
  selected=$(printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0))') || return $?
  start_contract=$(jq -r --argjson selected "$selected" --arg schema "${SCHEMA_SVCS[*]}" '
    .services as $services |
    def walk($name; $required; $path):
      if $path | index($name) then empty
      elif $services[$name] == null then
        if $required then error("missing required dependency: " + $name) else empty end
      else {name: $name, required: $required},
        (($services[$name].depends_on // {}) | to_entries[] |
          walk(.key; ($required and (.value.required != false)); $path + [$name]))
      end;
    (if $selected | length > 0 then $selected else $services | keys end) as $roots |
    [$roots[] | walk(.; true; [])] | group_by(.name) |
    map({name: .[0].name, required: any(.[]; .required)}) as $active |
    [$active[].name as $name | ($services[$name].depends_on // {}) | to_entries[] |
      select(.value.condition == "service_completed_successfully") | .key] as $completed |
    $active[] | .name as $name | $services[$name] as $service |
    [$name, .required,
      ((($schema | split(" ")) + $completed) | index($name) != null),
      ($service.healthcheck != null and $service.healthcheck.disable != true and
        ($service.healthcheck.test | type == "array" and length > 0) and
        $service.healthcheck.test[0] != "NONE"),
      ($service.scale // $service.deploy.replicas // 1)] | @tsv
  ' <<< "$model") || return $?
  [[ -n $start_contract ]] || { err "no services selected for startup"; return 1; }
  while IFS=$'\t' read -r service required oneshot health replicas; do
    start_services+=("$service")
    if [[ $required == true && $oneshot == false ]]; then
      start_long_running=1
      if [[ $health != true ]]; then
        err "$service needs an enabled Compose readiness healthcheck"; return 1
      fi
    fi
  done <<< "$start_contract"
  build_help=$("${compose_base[@]}" build --help) || return $?
  [[ $build_help == *--with-dependencies* ]] || {
    err "docker compose build --with-dependencies is required; update Compose"; return 1;
  }
  step "${compose_base[*]} build --with-dependencies $*"
  "${compose_base[@]}" build --with-dependencies "$@" &
  start_child=$!
  status=0; wait "$start_child" || status=$?
  start_child=''
  (( status == 0 )) || return "$status"

  start_deadline=$((SECONDS + start_timeout))
  step "${compose_base[*]} up -d --no-build $*"
  start_activated=1
  timeout --kill-after=2 "${start_timeout}s" "${compose_base[@]}" up -d --no-build "$@" &
  start_child=$!
  status=0; wait "$start_child" || status=$?
  start_child=''
  if (( status != 0 )); then
    err "activation failed or timed out (status $status); inspect the current stack"
    return "$status"
  fi
  while :; do
    compose_start_check || return $?
    (( ${#start_pending[@]} )) || break
    if (( SECONDS >= start_deadline )); then
      err "not ready within ${start_timeout}s: ${start_pending[*]}"; return 124
    fi
    sleep 1
  done
  ok "startup ready: ${start_services[*]}"
  (( start_attach )) || return 0

  say "${C_DIM}foreground — streaming logs; Ctrl-C stops the selected stack${C_RESET}"
  "${compose_base[@]}" logs --follow "${start_services[@]}" &
  start_child=$!
  while kill -0 "$start_child" 2>/dev/null; do
    start_deadline=$((SECONDS + start_timeout))
    status=0; compose_start_check || status=$?
    if (( status != 0 || ${#start_pending[@]} )); then
      err "runtime readiness lost; inspect the current stack"
      kill -TERM "$start_child" 2>/dev/null || true
      wait "$start_child" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
  status=0; wait "$start_child" || status=$?
  start_child=''
  (( status == 0 )) || return "$status"
  start_deadline=$((SECONDS + start_timeout))
  compose_start_check || return $?
  (( ${#start_pending[@]} == 0 )) || { err "runtime readiness lost"; return 1; }
  (( start_long_running == 0 )) || { err "foreground log stream ended unexpectedly"; return 1; }
  return "$status"
)
