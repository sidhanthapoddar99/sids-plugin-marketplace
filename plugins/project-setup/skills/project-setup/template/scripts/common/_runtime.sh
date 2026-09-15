#!/usr/bin/env bash

runtime_running_services() {
  dc ps --status running --services
}

runtime_service_running() {
  local services service
  services=$(runtime_running_services) || die "cannot query running services in the current Compose project"
  while IFS= read -r service; do
    [[ $service != "$1" ]] || return 0
  done <<< "$services"
  return 1
}

runtime_exec() {
  local -a options=()
  [[ -t 0 && -t 1 ]] || options+=(-T)
  dc exec "${options[@]}" "$@"
}

runtime_run() {
  local -a options=(--rm --no-deps)
  [[ -t 0 && -t 1 ]] || options+=(-T)
  dc run "${options[@]}" "$@"
}
