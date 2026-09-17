#!/usr/bin/env bash

# The Rust example has one watcher; remove this declaration when removing the app.
controller_names() {
  local app
  for app in "$@"; do
    if [[ $app == engine ]]; then printf '%s\n' engine; fi
  done
}
controller_command() { app_cmd "$1"; }
controller_probe() { app_ready_cmd "$1"; }
controller_timeout() { app_ready_timeout "$1"; }
