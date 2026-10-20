#!/usr/bin/env bash
# dev/stop.sh — `ctl stop`: everything this project owns. Recorded host groups first, then app
# containers, then the data core. `ctl dev stop --all` runs this worker.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/dev/_stop.sh"

usage() { print_help stop "Stop this project's managed host processes, then containers; keep data." \
  'stop [--dry-run] [-h]' \
  $'Options\n  --dry-run    list owned targets without stopping or cleaning records\n  -h, --help   show this help\n\nStops recorded dev groups, watchers and frozen servers before Docker services,\nthen app containers before the data core. Unrecorded port listeners are never killed.\nContainers and volumes are retained. Failures return nonzero; unresolved writers\nprevent database shutdown. To stop only the dev apps and keep the data core: ctl dev stop.'; }

dry=0
for argument in "$@"; do
  case "$argument" in
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $argument (try ctl stop --help)" ;;
  esac
done

load_env_files
expand_env_refs || exit 1
resolve_storage_dirs || exit 1
stop_host_processes "$dry" || die "host shutdown incomplete; containers left running to protect data"
stop_containers "$dry" apps data || die "host cleanup complete; container shutdown incomplete"
(( dry )) && exit 0
ok "project stopped; containers, data and volumes preserved"
