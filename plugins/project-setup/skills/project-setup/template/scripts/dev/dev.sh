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

# [ADAPT] the host apps — name → port → command. The ONE source for --help, --dry-run, and the run.
# Emitted as strings so help/dry-run print EXACTLY what runs (ports resolve from .env.proxy once loaded).
app_names() { printf '%s\n' api engine landing app docs dashboard single; }   # single = example-single-web-app-vite, the one-frontend shape
frontends() { printf '%s\n' landing app docs dashboard; }      # the ones the dev proxy fronts
# port_of VAR — the value from .env.proxy. Under --help the env may be absent: print the key name instead of dying.
port_of()   { local v="$1"; if [[ -n "${!v:-}" ]]; then echo "${!v}"; elif [[ "${HELP_MODE:-0}" == 1 ]]; then echo "\$$v"; else die "$v is blank in .env.proxy"; fi; }
app_port()  { case "$1" in
  api)       port_of API_PORT ;;          engine)    port_of ENGINE_PORT ;;
  landing)   port_of WEB_LANDING_PORT ;;  app)       port_of WEB_APP_PORT ;;
  single)    port_of WEB_APP_PORT ;;
  docs)      port_of WEB_DOCS_PORT ;;     dashboard) port_of DASHBOARD_PORT ;;
  *)         die "unknown app '$1' — one of: $(app_names | join_sp)" ;; esac; }
app_cmd()   { case "$1" in
  api)       printf 'uv run --directory apps/example-api-python uvicorn app.main:app --reload --host %s --port %s' "${API_HOST:-localhost}" "$(app_port api)" ;;
  engine)    printf 'cargo watch -C apps/example-engine-rust -x run' ;;
  landing)   printf 'bun --cwd apps/example-multi-web-app/landing dev --port %s' "$(app_port landing)" ;;
  app)       printf 'bun --cwd apps/example-multi-web-app/app dev --port %s' "$(app_port app)" ;;
  single)    printf 'bun --cwd apps/example-single-web-app-vite dev --port %s' "$(app_port single)" ;;
  docs)      printf 'bun --cwd apps/example-multi-web-app/docs dev --port %s' "$(app_port docs)" ;;
  dashboard) printf 'bun --cwd apps/example-dashboard-nextjs dev --port %s' "$(app_port dashboard)" ;;
  *)         die "unknown app '$1'" ;; esac; }

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

if (( dry )); then
  step "(dry-run — nothing started)"
  (( ${#DATA_SVCS[@]} && ! no_core )) && say "data core   ctl up preset $DEV_PRESET --nqa -y   → ctl up $(preset_args "$DEV_PRESET" || echo "(preset '$DEV_PRESET' missing from $PRESETS_FILE)")"
  (( proxy )) && say "dev proxy   docker compose --project-directory . -f $DEV_FILE up -d   → http://localhost:${DEV_PROXY_PORT:?DEV_PROXY_PORT is blank in .env.proxy}"
  for a in "${apps[@]}"; do say "$(printf '%-11s' "$a") $(app_cmd "$a")"; done
  exit 0
fi

require_tools mise

# data core — the same worker `ctl up` runs, with the dev line and no prompts. Skipped cleanly when
# DATA_SVCS is empty (no-data-core projects) or --no-core.
if (( ${#DATA_SVCS[@]} && ! no_core )); then
  require_docker
  preset_args "$DEV_PRESET" >/dev/null || die "preset '$DEV_PRESET' missing from $PRESETS_FILE — it is what ctl dev starts. Add:  $DEV_PRESET: \"--config db +expose_db\""
  step "ensuring data core (ctl up preset $DEV_PRESET)…"
  bash "$CTL_ROOT/scripts/container/up.sh" preset "$DEV_PRESET" --nqa -y
  wait_healthy "${DATA_SVCS[@]}" 60 || warn "health poll failed — continuing anyway."
  # nothing in the db config depends on the schema one-shots, so `up -d` returns while they run:
  # block until each has exited, and stop on a non-zero exit, because the apps would start on a stale schema
  if (( ${#SCHEMA_SVCS[@]} )); then
    step "schema step: waiting on ${SCHEMA_SVCS[*]}"
    dc wait "${SCHEMA_SVCS[@]}" >/dev/null || die "schema step failed — see: ctl logs ${SCHEMA_SVCS[*]}"
  fi
fi

# dev proxy — one origin across frontends. The foreground loop stops it on Ctrl-C; under --detach it
# stays up with the apps, and `ctl ps` → k on its port stops the container.
if (( proxy )); then
  require_docker
  step "starting dev proxy ($DEV_FILE) → http://localhost:${DEV_PROXY_PORT:?DEV_PROXY_PORT is blank in .env.proxy}"
  dc_dev up -d
fi

if (( detach )); then
  for a in "${apps[@]}"; do
    [[ -n "$(port_pid "$(app_port "$a")")" ]] && { warn "$a already listening on :$(app_port "$a") — skipping"; continue; }
    detach_run "dev-$a" "$CTL_ROOT" bash -c "$(app_cmd "$a")"
  done
  say "attach: ${C_B}ctl ps${C_RESET} → ${C_B}a${C_RESET}   ·   stop: ${C_B}ctl ps${C_RESET} → ${C_B}k${C_RESET}  (or ctl ps kill <port> -y)"
  exit 0
fi

step "starting host processes — Ctrl-C stops all"
prefix() { local t="$1" c="$2"; while IFS= read -r l; do printf '%s[%s]%s %s\n' "$c" "$t" "$C_RESET" "$l"; done; }
colors=("$C_YEL" "$C_CYN" "$C_GRN" "$C_DIM")
pids=(); i=0
for a in "${apps[@]}"; do
  ( bash -c "$(app_cmd "$a")" 2>&1 | prefix "$(printf '%-6s' "$a")" "${colors[i % 4]}" ) & pids+=($!); i=$((i+1))
done
stop_proxy() { (( proxy )) && dc_dev down >/dev/null 2>&1 || true; }
trap 'kill "${pids[@]}" 2>/dev/null || true; wait || true; stop_proxy; exit 0' INT TERM
wait
