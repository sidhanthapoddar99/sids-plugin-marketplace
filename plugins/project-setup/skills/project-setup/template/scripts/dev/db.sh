#!/usr/bin/env bash
# dev/db.sh — `ctl dev db`: the development data core on its own. It runs detached and outlives the
# host apps, so restarting them with `ctl dev` never stops, recreates or rebuilds it.
#
#   ctl dev db [--detach]   start the core (or reuse a running one), then apply migrations
#   ctl dev db stop         stop the core; refused while dev apps or app containers still run
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/dev/_stop.sh"
source "$CTL_ROOT/scripts/dev/_data-core.sh"

usage() { print_help "dev db" "Start or stop the development data core (${DATA_SVCS[*]:-none}) in Docker." \
  'dev db [-d|--detach] [--dry-run] [-h]
  ctl dev db stop [--dry-run] [-h]' \
"Commands
  (none)          start the data core detached with the reserved preset
                  (ctl up preset $DEV_PRESET --nqa -y --no-build), wait until every engine passes its
                  healthcheck, then apply migrations (ctl db migrate up). Already running: reuse it
                  as it is and migrate only.
  stop            stop the data-core containers. Containers, volumes and data are kept, so the next
                  start reuses them. Refused while ctl dev apps or app containers still run:
                  use ctl dev stop --all, or ctl stop.

Options
  -d, --detach    accepted for clarity; the data core always runs detached
  --dry-run, -n   print what would run or stop, change nothing
  -h, --help      show this help" \
"No engine image is built here. After changing an engine in docker/, restart the core: ctl dev db stop, then ctl dev db."; }

command=start dry=0
if [[ ${1:-} == stop ]]; then command=stop; shift; fi
while (( $# )); do case "$1" in
  -h|--help)    HELP_MODE=1 usage; exit 0 ;;
  -d|--detach)  [[ $command == start ]] || die "--detach applies to starting the data core"; shift ;;
  --dry-run|-n) dry=1; shift ;;
  *)            die "unknown argument '$1' (see ctl dev db -h)" ;;
esac; done
(( ${#DATA_SVCS[@]} )) || { ok "no data core configured (DATA_SVCS is empty)"; exit 0; }

if [[ $command == stop ]]; then
  load_env_files
  expand_env_refs || exit 1
  resolve_storage_dirs || exit 1
  stop_data_core "$dry" || die "data core not stopped"
  if (( dry )); then ok "dry-run complete; nothing stopped"; else ok "data core stopped; containers and data preserved"; fi
  exit 0
fi

require_env
resolve_storage_dirs
if (( dry )); then
  step "(dry-run — nothing started)"
  data_core_plan
  exit 0
fi
ensure_data_core 0
ok "data core ready (detached); stop it with ctl dev db stop"
