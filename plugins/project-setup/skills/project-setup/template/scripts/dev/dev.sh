#!/usr/bin/env bash
# dev/dev.sh — `ctl dev [app…]`. The host dev loop: the data core in docker (compose.db.yaml
# alone — loopback ports, so host processes reach it), the apps on the host with reload.
#
#   ctl dev                 every app, foreground, prefixed output — Ctrl-C stops all
#   ctl dev api app         only these apps
#   ctl dev --proxy         also run the nginx dev proxy (docker/compose.dev.yaml, host network) so every
#                           frontend + backend sits on ONE origin: http://localhost:$DEV_PROXY_PORT.
#                           Turned on automatically when two or more frontends are selected.
#   ctl dev --detach        background them: logs → data/logs/dev-<app>.log, pids → data/run/
#                           attach with `ctl ps` → a · stop with `ctl ps` → k (or ctl ps kill)
#   ctl dev --dry-run       print the data-core bring-up + the host commands, run nothing
#
# Migrations are NOT run here — `ctl migrate` is an explicit step.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] the host apps — name → port → command. The ONE source for --help, --dry-run, and the run.
# Emitted as strings so help/dry-run print EXACTLY what runs (ports resolve from .env once loaded).
app_names() { printf '%s\n' api engine landing app docs dashboard; }
frontends() { printf '%s\n' landing app docs dashboard; }      # the ones the dev proxy fronts
app_port()  { case "$1" in
  api)       echo "${API_PORT:-8000}" ;;          engine)    echo "${ENGINE_PORT:-8080}" ;;
  landing)   echo "${WEB_LANDING_PORT:-3001}" ;;  app)       echo "${WEB_APP_PORT:-5173}" ;;
  docs)      echo "${WEB_DOCS_PORT:-4321}" ;;     dashboard) echo "${DASHBOARD_PORT:-3000}" ;;
  *)         die "unknown app '$1' — one of: $(app_names | join_sp)" ;; esac; }
app_cmd()   { case "$1" in
  api)       printf 'uv run --directory apps/example-api-python uvicorn app.main:app --reload --host %s --port %s' "${API_HOST:-localhost}" "$(app_port api)" ;;
  engine)    printf 'cargo watch -C apps/example-engine-rust -x run' ;;
  landing)   printf 'bun --cwd apps/example-multi-web-app/landing dev --port %s' "$(app_port landing)" ;;
  app)       printf 'bun --cwd apps/example-multi-web-app/app dev --port %s' "$(app_port app)" ;;
  docs)      printf 'bun --cwd apps/example-multi-web-app/docs dev --port %s' "$(app_port docs)" ;;
  dashboard) printf 'bun --cwd apps/example-dashboard-nextjs dev --port %s' "$(app_port dashboard)" ;;
  *)         die "unknown app '$1'" ;; esac; }

usage() { print_help "dev" "Data core in docker, apps on the host with reload." \
  'dev [app…] [-d|--detach] [--proxy] [--no-core] [--dry-run] [-h]' \
"Arguments
  app…            which apps to run — default: all ($(app_names | join_sp))

Direct  (the host command each app runs — what --dry-run prints; copy to run without ctl)
$(for a in $(app_names); do printf '  %-8s %s%s%s\n' "$a" "$C_GRN" "$(app_cmd "$a")" "$C_RESET"; done)

Options
  -d, --detach    run in the BACKGROUND: logs → data/logs/dev-<app>.log, pidfiles → data/run/.
                  Attach with 'ctl ps' → a; stop with 'ctl ps' → k (or ctl ps kill <port>).
  --proxy         also run the nginx dev proxy ($DEV_FILE, host network): one origin at
                  http://localhost:\${DEV_PROXY_PORT} routing every prefix to its dev server.
                  Automatic when two or more frontends ($(frontends | join_sp)) are selected.
  --no-core       don't touch the data core; assume it is reachable
  --dry-run, -n   print what would run, run nothing
  -h, --help      show this help

With a data core (DATA_SVCS set) it first runs \`docker compose -f $DB_FILE up -d\` and
waits for health, then starts the host processes."; }

# parse: positionals = apps, flags anywhere
apps=() dry=0 detach=0 no_core=0 proxy=0
while (( $# )); do case "$1" in
  -h|--help)     usage; exit 0 ;;
  --dry-run|-n)  dry=1; shift ;;
  -d|--detach)   detach=1; shift ;;
  --proxy)       proxy=1; shift ;;
  --no-core)     no_core=1; shift ;;
  -*)            die "unknown flag '$1' (see ctl dev -h)" ;;
  *)             app_names | grep -qx "$1" || die "unknown app '$1' — one of: $(app_names | join_sp)"; apps+=("$1"); shift ;;
esac; done
(( ${#apps[@]} )) || mapfile -t apps < <(app_names)
# two or more frontends selected → they need one origin → the dev proxy comes up
n_fe=0; for a in "${apps[@]}"; do frontends | grep -qx "$a" && n_fe=$((n_fe+1)); done
(( n_fe >= 2 )) && proxy=1

require_env

if (( dry )); then
  step "(dry-run — nothing started)"
  (( ${#DATA_SVCS[@]} && ! no_core )) && say "data core   docker compose --project-directory . -f $DB_FILE up -d ${DATA_SVCS[*]}"
  (( proxy )) && say "dev proxy   docker compose --project-directory . -f $DEV_FILE up -d   → http://localhost:${DEV_PROXY_PORT:-3080}"
  for a in "${apps[@]}"; do say "$(printf '%-11s' "$a") $(app_cmd "$a")"; done
  exit 0
fi

require_tools mise

# data core — skipped cleanly when DATA_SVCS is empty (no-data-core projects) or --no-core
if (( ${#DATA_SVCS[@]} && ! no_core )); then
  require_docker
  step "ensuring data core ($DB_FILE)…"
  dc_db up -d "${DATA_SVCS[@]}"
  wait_healthy "${DATA_SVCS[@]}" 60 || warn "health poll failed — continuing anyway."
fi

# dev proxy — one origin across frontends. The foreground loop stops it on Ctrl-C; under --detach it
# stays up with the apps, and `ctl ps` → k on its port stops the container.
if (( proxy )); then
  require_docker
  step "starting dev proxy ($DEV_FILE) → http://localhost:${DEV_PROXY_PORT:-3080}"
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
