#!/usr/bin/env bash
# dev/dev.sh — `ctl dev [app…]`. The host dev loop: the data core in docker, the apps on the host
# with reload. The data core is `ctl up preset dev`, a reserved line in docker/presets.yaml (the db
# config bound to loopback so host processes reach it). Its schema one-shots run with it, so the loop
# starts on a migrated schema. Edit the preset to change what `ctl dev` starts; a missing one is an error.
#
#   ctl dev                 in a terminal: pick the apps (multi-select, all preselected), then run them
#                           foreground with prefixed output — Ctrl-C stops all. No TTY or --nqa: every app.
#   ctl dev api app         only these apps, no prompt
#   ctl dev --proxy         also run the nginx dev proxy (docker/compose.dev.yaml, host network) so every
#                           frontend + backend sits on ONE origin: http://localhost:$DEV_PROXY_PORT.
#                           Turned on automatically when two or more frontends are selected.
#   ctl dev --detach        background them: logs → logs/dev/dev-<app>.log, pids → logs/run/
#                           attach with `ctl ps` → a · stop with `ctl ps` → k (or ctl ps kill)
#   ctl dev --dry-run       print the data-core bring-up + the host commands, run nothing
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

source "$CTL_ROOT/scripts/dev/_apps.sh"

usage() { print_help "dev" "Data core in docker, apps on the host with reload." \
  'dev [app…] [-d|--detach] [--proxy] [--no-core] [--nqa] [--dry-run] [-h]' \
"Arguments
  app…            which apps to run: $(app_names | join_sp)
                  (none given: interactive pick in a terminal, all preselected; else every app)

Direct  (the host command each app runs — what --dry-run prints; copy to run without ctl)
$(for a in $(app_names); do printf '  %-10s %s%s%s\n' "$a" "$C_GRN" "$(app_cmd "$a")" "$C_RESET"; done)

Options
  -d, --detach    run in the BACKGROUND: logs → logs/dev/dev-<app>.log, pidfiles → logs/run/.
                  Attach with 'ctl ps' → a; stop with 'ctl ps' → k (or ctl ps kill <port>).
  --proxy         also run the nginx dev proxy ($DEV_FILE, host network): one origin at
                  http://localhost:\${DEV_PROXY_PORT} routing every prefix to its dev server.
                  Automatic when two or more frontends ($(frontends | join_sp)) are selected.
  --no-core       don't touch the data core; assume it is reachable
  --nqa           no questions — skip the app picker; no apps named = every app
  --dry-run, -n   print what would run, run nothing
  -h, --help      show this help

With a data core (DATA_SVCS set) it first runs \`ctl up preset $DEV_PRESET --nqa -y\` (the reserved preset in
$PRESETS_FILE: the engines bound to loopback, the schema one-shots with them), waits for health and
for the schema step, then starts the host processes."; }

# parse: positionals = apps, flags anywhere
apps=() dry=0 detach=0 no_core=0 proxy=0 nqa=0
while (( $# )); do case "$1" in
  -h|--help)     HELP_MODE=1 usage; exit 0 ;;
  --dry-run|-n)  dry=1; shift ;;
  -d|--detach)   detach=1; shift ;;
  --proxy)       proxy=1; shift ;;
  --no-core)     no_core=1; shift ;;
  --nqa|--no-questions-asked) nqa=1; shift ;;
  -*)            die "unknown flag '$1' (see ctl dev -h)" ;;
  *)             app_names | grep -qx "$1" || die "unknown app '$1' — one of: $(app_names | join_sp)"; apps+=("$1"); shift ;;
esac; done
# no apps named: pick in a terminal (same widget as `ctl up`), else every app
if (( ${#apps[@]} == 0 )); then
  mapfile -t ALL_APPS < <(app_names)
  if [[ -t 1 && -r /dev/tty && $nqa -eq 0 && $dry -eq 0 ]]; then
    tui_select --into apps --multi --preselect "$(IFS=,; echo "${ALL_APPS[*]}")" \
      --header "Apps — untick what should not run (Enter = every ticked one)" -- "${ALL_APPS[@]}" \
      || { say "cancelled."; exit 0; }
    printf '\n'
    (( ${#apps[@]} )) || die "no app selected — nothing to run"
  else apps=("${ALL_APPS[@]}"); fi
fi
# two or more frontends selected → they need one origin → the dev proxy comes up
n_fe=0; for a in "${apps[@]}"; do frontends | grep -qx "$a" && n_fe=$((n_fe+1)); done
(( n_fe >= 2 )) && proxy=1

require_env
resolve_storage_dirs

if (( dry )); then
  step "(dry-run — nothing started)"
  (( ${#DATA_SVCS[@]} && ! no_core )) && say "data core   ctl up preset $DEV_PRESET --nqa -y   → ctl up $(preset_args "$DEV_PRESET" || echo "(preset '$DEV_PRESET' missing from $PRESETS_FILE)")"
  (( proxy )) && say "dev proxy   docker compose --project-directory . -f $DEV_FILE up -d   → http://localhost:${DEV_PROXY_PORT:?DEV_PROXY_PORT is blank in .env}"
  for a in "${apps[@]}"; do say "$(printf '%-11s' "$a") $(app_cmd "$a")"; done
  exit 0
fi

for a in "${apps[@]}"; do
  mapfile -t app_requirements < <(app_tools "$a")
  require_tools "${app_requirements[@]}"
done
process_init
proxy_owned=0
proxy_before=""
proxy_command() {
  local limit="$1"; shift
  timeout --kill-after=2 "$limit" bash -c '
    source "$1/scripts/common/_lib.sh"; shift
    cd "$CTL_ROOT"; require_env; dc_dev "$@"
  ' bash "$CTL_ROOT" "$@"
}
dev_cleanup() {
  process_cleanup
  local container
  if (( proxy_owned )); then
    for container in $(proxy_command 5 ps -q 2>/dev/null); do
      [[ " $proxy_before " == *" $container "* ]] && continue
      timeout --kill-after=1 5 docker stop "$container" >/dev/null 2>&1 || true
    done
  fi
}
trap 'dev_cleanup' EXIT

# data core — the same worker `ctl up` runs, with the dev line and no prompts. Skipped cleanly when
# DATA_SVCS is empty (no-data-core projects) or --no-core.
if (( ${#DATA_SVCS[@]} && ! no_core )); then
  require_docker
  preset_args "$DEV_PRESET" >/dev/null || die "preset '$DEV_PRESET' missing from $PRESETS_FILE — it is what ctl dev starts. Add:  $DEV_PRESET: \"--config db +expose_db\""
  step "ensuring data core (ctl up preset $DEV_PRESET)…"
  bash "$CTL_ROOT/scripts/container/up.sh" preset "$DEV_PRESET" --nqa -y
fi

# dev proxy — one origin across frontends. The foreground loop stops it on Ctrl-C; under --detach it
# stays up with the apps, and `ctl ps` → k on its port stops the container.
if (( proxy )); then
  require_docker
  require_tools curl
  step "starting dev proxy ($DEV_FILE) → http://localhost:${DEV_PROXY_PORT:?DEV_PROXY_PORT is blank in .env}"
  proxy_before=$(proxy_command 5 ps -q | tr '\n' ' ')
  if [[ -z $proxy_before ]]; then
    proxy_owned=1
    proxy_command 60 up -d
  fi
  printf -v proxy_probe 'curl --fail --silent --max-time 1 %q' "http://localhost:${DEV_PROXY_PORT}/_ctl/ready"
  process_ready 30 "$proxy_probe" || exit $?
fi

for a in "${apps[@]}"; do
  probe="$(app_ready_cmd "$a")"
  if [[ -n "$(port_pid "$(app_port "$a")")" ]]; then
    process_ready "$(app_ready_timeout "$a")" "$probe" || exit $?
    ok "$a already ready — skipping"
    continue
  fi
  step "starting $a — log: $LOGS_DIR/dev/dev-$a.log"
  process_start "dev-$a" "$CTL_ROOT" bash -c "$(app_cmd "$a")"
  if (( ! detach )); then
    process_start "follow-dev-$a-$$" "$CTL_ROOT" bash -c 'tail -n +1 -s .1 -f "$1" | while IFS= read -r line; do printf "[%s] %s\n" "$2" "$line" >&3; done' bash "$LOGS_DIR/dev/dev-$a.log" "$a" 3>&1
  fi
  process_ready "$(app_ready_timeout "$a")" "$probe" || exit $?
  ok "$a ready — log: $LOGS_DIR/dev/dev-$a.log"
done

if (( detach )); then
  process_check_all
  process_release
  proxy_owned=0
  say "attach: ctl ps → a   ·   stop: ctl ps kill <port> -y"
  exit 0
fi

(( ${#PROCESS_RECORDS[@]} )) || exit 0
step "host processes ready — Ctrl-C stops this launch"
process_monitor
