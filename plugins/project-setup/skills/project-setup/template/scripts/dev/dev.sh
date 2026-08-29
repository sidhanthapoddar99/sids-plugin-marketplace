#!/usr/bin/env bash
# dev/dev.sh — `ctl dev [app…]`. The host dev loop: the data core in docker (compose.db.yaml
# alone — loopback ports, so host processes reach it), the apps on the host with reload.
#
#   ctl dev                 every app, foreground, prefixed output — Ctrl-C stops all
#   ctl dev api web         only these apps
#   ctl dev --detach        background them: logs → data/logs/dev-<app>.log, pids → data/run/
#                           attach with `ctl ps` → a · stop with `ctl ps` → k (or ctl ps kill)
#   ctl dev --dry-run       print the data-core bring-up + the host commands, run nothing
#
# Migrations are NOT run here — `ctl migrate` is an explicit step.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] the host apps — name → port → command. The ONE source for --help, --dry-run, and the run.
# Emitted as strings so help/dry-run print EXACTLY what runs (ports resolve from .env once loaded).
app_names() { printf '%s\n' api engine web site; }
app_port()  { case "$1" in
  api)    echo "${API_PORT:-8000}" ;;     engine) echo "${ENGINE_PORT:-8080}" ;;
  web)    echo "${WEB_PORT:-5173}" ;;     site)   echo "${SITE_PORT:-3000}" ;;
  *)      die "unknown app '$1' — one of: $(app_names | join_sp)" ;; esac; }
app_cmd()   { case "$1" in
  api)    printf 'uv run --directory apps/api uvicorn app.main:app --reload --host %s --port %s' "${API_HOST:-localhost}" "$(app_port api)" ;;
  engine) printf 'cargo watch -C apps/engine -x run' ;;
  web)    printf 'bun --cwd apps/web dev --port %s' "$(app_port web)" ;;
  site)   printf 'bun --cwd apps/site dev --port %s' "$(app_port site)" ;;
  *)      die "unknown app '$1'" ;; esac; }

usage() { print_help "dev" "Data core in docker, apps on the host with reload." \
  'dev [app…] [-d|--detach] [--no-core] [--dry-run] [-h]' \
"Arguments
  app…            which apps to run — default: all ($(app_names | join_sp))

Direct  (the host command each app runs — what --dry-run prints; copy to run without ctl)
$(for a in $(app_names); do printf '  %-8s %s%s%s\n' "$a" "$C_GRN" "$(app_cmd "$a")" "$C_RESET"; done)

Options
  -d, --detach    run in the BACKGROUND: logs → data/logs/dev-<app>.log, pidfiles → data/run/.
                  Attach with 'ctl ps' → a; stop with 'ctl ps' → k (or ctl ps kill <port>).
  --no-core       don't touch the data core; assume it is reachable
  --dry-run, -n   print what would run, run nothing
  -h, --help      show this help

With a data core (DATA_SVCS set) it first runs \`docker compose -f $DB_FILE up -d\` and
waits for health, then starts the host processes."; }

# parse: positionals = apps, flags anywhere
apps=() dry=0 detach=0 no_core=0
while (( $# )); do case "$1" in
  -h|--help)     usage; exit 0 ;;
  --dry-run|-n)  dry=1; shift ;;
  -d|--detach)   detach=1; shift ;;
  --no-core)     no_core=1; shift ;;
  -*)            die "unknown flag '$1' (see ctl dev -h)" ;;
  *)             app_names | grep -qx "$1" || die "unknown app '$1' — one of: $(app_names | join_sp)"; apps+=("$1"); shift ;;
esac; done
(( ${#apps[@]} )) || mapfile -t apps < <(app_names)

require_env

if (( dry )); then
  step "(dry-run — nothing started)"
  (( ${#DATA_SVCS[@]} && ! no_core )) && say "data core   docker compose --project-directory . -f $DB_FILE up -d ${DATA_SVCS[*]}"
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
trap 'kill "${pids[@]}" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
