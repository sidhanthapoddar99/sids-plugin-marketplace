#!/usr/bin/env bash
# docker-up.sh — `ctl up`. Assemble the container stack from profiles + one --config + .m. modifiers.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "up" "Start the container stack: profiles + one --config + stacked .m. modifiers." \
  'up [profile…] [--config=<name>] [--<modifier>…] [--dry-run] [-h]' \
"Arguments
  profile…            services to run; combine freely (bare = no-profile data core)
  --config=<name>     one alternate deployment config (compose.<name>.yaml)
  --<modifier>        a .m. overlay (compose.m.<modifier>.yaml); stack freely
  --dry-run, -n       print the composed docker-compose command, don't run it
  -h, --help          show this help

Discovered in docker/:
  profiles    $(list_profiles  | join_sp)
  configs     $(list_configs   | sed 's/^/--config=/' | join_sp)
  modifiers   $(list_modifiers | sed 's/^/--/'        | join_sp)" \
"Example:  ctl up app edge --config=prod --traefik"; }

is_help "${1:-}" && { usage; exit 0; }
require_env

profiles=() config="" modifiers=() dry=0
while (( $# )); do
  case "$1" in
    --dry-run|-n) dry=1; shift ;;
    --config=*)   [[ -z $config ]] || die "one --config at a time"; config="${1#--config=}"; shift ;;
    --config)     [[ -z $config ]] || die "one --config at a time"; config="${2:-}"; shift 2 ;;
    --*)          modifiers+=("${1#--}"); shift ;;        # --expose → modifier 'expose'
    -*)           die "unknown flag: $1 (try ctl up --help)" ;;
    *)            profiles+=("$1"); shift ;;
  esac
done

files=("$BASE") prof=() envf=()
if [[ -n $config ]]; then                                # base → config → modifiers (modifiers win)
  cf="$DOCKER_DIR/compose.$config.yaml"
  [[ -f $cf ]] || die "no such config '$config'. configs: $(list_configs | join_sp)"
  files+=("$cf")
  [[ $config == prod && -f .env.production ]] && envf=(--env-file .env.production)
fi
for m in "${modifiers[@]}"; do
  mf="$DOCKER_DIR/compose.m.$m.yaml"
  [[ -f $mf ]] || die "no such modifier '$m'. modifiers: $(list_modifiers | join_sp)"
  files+=("$mf")
done
for p in "${profiles[@]}"; do
  list_profiles | grep -qx "$p" || die "no such profile '$p'. profiles: $(list_profiles | join_sp)"
  prof+=(--profile "$p")
done

cmd=(docker compose); for f in "${files[@]}"; do cmd+=(-f "$f"); done
cmd+=("${prof[@]}" "${envf[@]}" up -d)
(( dry )) && { say "${cmd[*]}"; exit 0; }                # --dry-run: print, don't run
step "${cmd[*]}"                                         # always echo the composed command
"${cmd[@]}"
ok "stack up"
