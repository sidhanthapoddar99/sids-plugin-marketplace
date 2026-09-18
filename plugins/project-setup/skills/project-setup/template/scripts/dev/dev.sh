#!/usr/bin/env bash
# dev/dev.sh — `ctl dev [app…]`. The host dev loop: the data core in docker, the apps on the host
# with reload. The dev preset selects engines and migration jobs from base, with loopback ports.
# Frontend dev servers own their HTTP/WebSocket proxies; production routing lives in Nginx.
#
#   ctl dev                 in a terminal: pick the apps (multi-select, all preselected), then run them
#                           foreground with prefixed output — Ctrl-C stops all. No TTY or --nqa: every app.
#   ctl dev api app         only these apps, no prompt
#   ctl dev --detach        background them: logs → logs/dev/dev-<app>.log, pids → logs/run/
#                           attach with `ctl ps` → a · stop with `ctl ps` → k (or ctl ps kill)
#   ctl dev --dry-run       print the data-core bring-up + the host commands, run nothing
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

source "$CTL_ROOT/scripts/dev/_apps.sh"
source "$CTL_ROOT/scripts/dev/_controllers.sh"

usage() { print_help "dev" "Data core in docker, apps on the host with reload." \
  'dev [app…] [-d|--detach] [--no-core] [--nqa] [--dry-run] [-h]' \
"Arguments
  app…            which apps to run: $(app_names | join_sp)
                  (none given: interactive pick in a terminal, all preselected; else every app)

Direct  (the host command each app runs — what --dry-run prints; copy to run without ctl)
$(for a in $(app_names); do printf '  %-10s %s%s%s\n' "$a" "$C_GRN" "$(app_cmd "$a")" "$C_RESET"; done)

Options
  -d, --detach    run in the BACKGROUND: logs → logs/dev/dev-<app>.log, pidfiles → logs/run/.
                  Attach with 'ctl ps' → a; stop with 'ctl ps' → k (or ctl ps kill <port>).
  --no-core       don't touch the data core; assume it is reachable
  --nqa           no questions — skip the app picker; no apps named = every app
  --dry-run, -n   print what would run, run nothing
  -h, --help      show this help

With a data core (DATA_SVCS set) it first runs \`ctl up preset $DEV_PRESET --nqa -y\` (the service subset in
$PRESETS_FILE: engines bound to loopback and their schema one-shots, without application containers), waits for health and
for the schema step, then starts the host processes.
Before startup, validate configuration and synchronize source dependencies with locked versions.
Missing settings point to ctl setup. Help and dry-run do not install anything."; }

# parse: positionals = apps, flags anywhere
apps=() dry=0 detach=0 no_core=0 nqa=0
while (( $# )); do case "$1" in
  -h|--help)     HELP_MODE=1 usage; exit 0 ;;
  --dry-run|-n)  dry=1; shift ;;
  -d|--detach)   detach=1; shift ;;
  --proxy)       die "--proxy is not supported; use the frontend dev server proxy" ;;
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
require_env
resolve_storage_dirs

if (( dry )); then
  step "(dry-run — nothing started)"
  say "preflight   validate configuration → synchronize source dependencies"
  (( ${#DATA_SVCS[@]} && ! no_core )) && say "data core   ctl up preset $DEV_PRESET --nqa -y   → ctl up $(preset_args "$DEV_PRESET" || echo "(preset '$DEV_PRESET' missing from $PRESETS_FILE)")"

  while IFS= read -r controller; do
    [[ -n $controller ]] || continue
    say "controller $controller   $(controller_command "$controller")"
  done < <(controller_names "${apps[@]}")
  for a in "${apps[@]}"; do say "$(printf '%-11s' "$a") $(app_cmd "$a")"; done
  exit 0
fi

source "$CTL_ROOT/scripts/config/_validate-env.sh"
validate_dev_env
source "$CTL_ROOT/scripts/config/_discovery.sh"
step "ensuring configured toolchains and dependencies"
sync_source_dependencies --locked || die "dependency synchronization failed — resolve the error above; update a stale lockfile with its package manager"

for a in "${apps[@]}"; do
  mapfile -t app_requirements < <(app_tools "$a")
  require_tools "${app_requirements[@]}"
done
process_init

# data core — the same worker `ctl up` runs, with the dev line and no prompts. Skipped cleanly when
# DATA_SVCS is empty (no-data-core projects) or --no-core.
if (( ${#DATA_SVCS[@]} && ! no_core )); then
  require_docker
  preset_args "$DEV_PRESET" >/dev/null || die "preset '$DEV_PRESET' missing from $PRESETS_FILE — it is what ctl dev starts. Add:  $DEV_PRESET: \"--config base +expose_db --services postgres,redis,neo4j,migrate,neo4j-init\""
  step "ensuring data core (ctl up preset $DEV_PRESET)…"
  bash "$CTL_ROOT/scripts/container/up.sh" preset "$DEV_PRESET" --nqa -y
fi

controllers=$(controller_names "${apps[@]}") || die "cannot resolve development controllers"
while IFS= read -r controller; do
  [[ -n $controller ]] || continue
  controller_ensure "$controller" || die "controller $controller is not ready; no apps launched"
done <<< "$controllers"

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
  say "attach: ctl ps → a   ·   stop: ctl ps kill <port> -y"
  exit 0
fi

(( ${#PROCESS_RECORDS[@]} )) || exit 0
step "host processes ready — Ctrl-C stops this launch"
process_monitor
