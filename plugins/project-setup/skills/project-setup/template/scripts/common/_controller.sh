#!/usr/bin/env bash

controller_ensure() {
  local name="$1" record command probe attempt
  [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || return 1
  mkdir -p "$LOGS_DIR/run" || return 1
  record="$LOGS_DIR/run/controller-$name.process"
  probe=$(controller_probe "$name") || return 1
  [[ -n $probe ]] || return 1
  if ! controller_lock_acquire "$LOGS_DIR/run/controller-$name.owner.lock"; then
    for attempt in {1..40}; do
      process_valid "$record" && break
      sleep 0.05
    done
    process_valid "$record" && process_owned "$record" "$CTL_ROOT" || {
      err "controller $name lock is held but its owner is unverified"; return 1;
    }
    process_ready "$(controller_timeout "$name")" "$probe" || return $?
    process_valid "$record" || return 1
    ok "controller $name already managed and ready"
    return 0
  fi
  if process_valid "$record"; then
    controller_lock_release
    err "controller $name is live without a verified ownership lock; refusing a duplicate"
    return 1
  fi
  if ! process_stop "$record" "$CTL_ROOT"; then controller_lock_release; return 1; fi
  command=$(controller_command "$name") || { controller_lock_release; return 1; }
  if ! process_start "controller-$name" "$CTL_ROOT" bash -c "$command"; then
    controller_lock_release; return 1
  fi
  controller_lock_release
  process_ready "$(controller_timeout "$name")" "$probe"
}
