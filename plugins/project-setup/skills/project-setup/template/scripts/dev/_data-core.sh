#!/usr/bin/env bash
# dev/_data-core.sh — the development data core: the DATA_SVCS engines that the reserved DEV_PRESET
# starts. Shared by `ctl dev`, `ctl dev db` and `ctl dev stop`. Sourced after _lib.sh and
# dev/_stop.sh. The core runs detached and outlives the host apps: `ctl dev` reuses a running
# core and never stops, recreates or rebuilds it. Only `ctl dev db stop`, `ctl dev stop --all`
# and `ctl stop` stop it.

# can_ask <nqa> — a person can answer a prompt: a terminal, and --nqa not given.
can_ask() { [[ -t 1 && -r /dev/tty && $1 -eq 0 ]]; }

# ask_yes <question> <default y|n> — [Y/n] or [y/N] on the terminal; Enter takes the default.
ask_yes() {
  local answer hint='[y/N]'; [[ $2 == y ]] && hint='[Y/n]'
  printf '%s?%s %s %s ' "$C_YEL" "$C_RESET" "$1" "$hint"
  IFS= read -r answer < /dev/tty || answer=""
  [[ -n $answer ]] || answer=$2
  [[ ${answer,,} == y || ${answer,,} == yes ]]
}

# data_core_up — every DATA_SVCS engine runs and passes its healthcheck.
data_core_up() {
  local service
  for service in "${DATA_SVCS[@]}"; do
    [[ $(svc_health "$service") =~ ^(healthy|running)$ ]] || return 1
  done
}

# data_core_unpublished — print each running engine that publishes no host port. Host apps reach
# the engines only through the loopback ports the dev preset publishes. An engine without one was
# started by another stack shape, such as `ctl up`, and a host app would reach whatever else holds
# that port. Returns 1 when Docker cannot answer, because a guess here could point the apps at a
# stranger's database. [ADAPT] keep every DATA_SVCS engine published by the dev preset.
data_core_unpublished() {
  local service identifier ports
  for service in "${DATA_SVCS[@]}"; do
    identifier=$(dc ps --quiet "$service") || return 1
    identifier=${identifier%%$'\n'*}
    [[ -n $identifier ]] || return 1
    ports=$(docker inspect --format '{{range $port, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{.HostPort}} {{end}}{{end}}' "$identifier") || return 1
    [[ -n ${ports//[[:space:]]/} ]] || printf '%s\n' "$service"
  done
}

# migrate_data_core — the schema step: `ctl db migrate up`, Flyway and then the other engines'
# initializers. It runs on every `ctl dev`, because a running core can still lack this checkout's
# newest migration and the apps must not start on an older schema. The migration image carries
# the SQL, so the step builds it from the layer cache: an unchanged checkout rebuilds nothing.
# Empty SCHEMA_SVCS = no schema step.
migrate_data_core() {
  (( ${#SCHEMA_SVCS[@]} )) || return 0
  step "applying migrations (ctl db migrate up)"
  bash "$CTL_ROOT/scripts/db/migrate.sh" up || die "migrations failed — the apps were not started; see the output above"
}

# start_data_core — the reserved preset, detached, without an image build. `ctl up` waits until
# every engine passes its healthcheck within its startup budget.
start_data_core() {
  preset_args "$DEV_PRESET" >/dev/null || die "preset '$DEV_PRESET' missing from $PRESETS_FILE — it is what ctl dev starts. Add:  $DEV_PRESET: \"--config base +expose_db --services $(IFS=,; echo "${DATA_SVCS[*]}")\""
  step "starting the data core (ctl up preset $DEV_PRESET --nqa -y --no-build)"
  bash "$CTL_ROOT/scripts/container/up.sh" preset "$DEV_PRESET" --nqa -y --no-build \
    || die "the data core did not start — see the output above; ctl logs <service> shows an engine's log"
}

# ensure_data_core <ask 0|1> — reuse a running core, or start a stopped one (after asking, when
# ask is 1), then apply migrations. A running core is never restarted.
ensure_data_core() {
  local ask=$1 unpublished
  require_docker
  if data_core_up; then
    unpublished=$(data_core_unpublished) || die "cannot read the data core's published ports from Docker"
    if [[ -n $unpublished ]]; then
      die "the data core runs without loopback ports ($(join_sp <<< "$unpublished")), so host apps cannot reach it — another stack shape such as ctl up started it. ctl dev never restarts a running core: stop it with ctl stop, then run ctl dev again"
    fi
    ok "data core running: ${DATA_SVCS[*]} — reused, not restarted"
  else
    if (( ask )); then
      ask_yes "The database is not running. Start it with 'ctl dev db --detach'" y \
        || die "the apps need the database — start it with: ctl dev db --detach"
    fi
    start_data_core
  fi
  migrate_data_core
}

# stop_data_core <dry> — stop the engines and nothing else. Refused while a recorded host process or
# an app container still runs, because a database must never stop under a live writer. A record ctl
# cannot verify counts as live, because a writer nobody can see must not lose its database.
stop_data_core() {
  local dry=$1 live
  if live=$(process_live_records); then
    err "ctl dev apps still run on the data core (${live//$'\n'/; }) — stop them first with ctl dev stop, or stop both with ctl dev stop --all"
    return 1
  fi
  stop_containers "$dry" data
}

# data_core_plan — what `ctl dev` and `ctl dev db` do with the core, for --dry-run.
data_core_plan() {
  say "data core   running → reuse it, never restart it; down → ctl up preset $DEV_PRESET --nqa -y --no-build → ctl up $(preset_args "$DEV_PRESET" || echo "(preset '$DEV_PRESET' missing from $PRESETS_FILE)")"
  (( ${#SCHEMA_SVCS[@]} )) || return 0
  say "migrations  ctl db migrate up, every time"
}
