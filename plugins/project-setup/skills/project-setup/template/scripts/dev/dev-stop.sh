#!/usr/bin/env bash
# dev/dev-stop.sh — `ctl dev stop`: stop the host processes ctl started for this checkout, and the
# data core only when asked. Keeping the database up lets the next `ctl dev` start without waiting
# for it. `--all` is `ctl stop`, so the two can never drift apart.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/dev/_stop.sh"
source "$CTL_ROOT/scripts/dev/_data-core.sh"

usage() { print_help "dev stop" "Stop the ctl dev apps; optionally the data core too." \
  'dev stop [--all] [--nqa] [--dry-run] [-h]' \
"Stops the host processes ctl started for this checkout: dev apps, watchers and frozen builds.
In a terminal it then asks whether to stop the data core as well (ctl dev db stop). Enter keeps
the database running.

Options
  --all           stop everything without asking: host processes, app containers and the data
                  core (= ctl stop)
  --nqa           no questions — keep the data core running
  --dry-run, -n   list what would stop, stop nothing
  -h, --help      show this help" \
"No terminal behaves like --nqa. Containers, volumes and data are always kept."; }

all=0 nqa=0 dry=0
while (( $# )); do case "$1" in
  -h|--help)    HELP_MODE=1 usage; exit 0 ;;
  --all)        all=1; shift ;;
  --nqa|--no-questions-asked) nqa=1; shift ;;
  --dry-run|-n) dry=1; shift ;;
  *)            die "unknown argument '$1' (see ctl dev stop -h)" ;;
esac; done
if (( all )); then
  if (( dry )); then exec bash "$CTL_ROOT/scripts/dev/stop.sh" --dry-run; fi
  exec bash "$CTL_ROOT/scripts/dev/stop.sh"
fi

load_env_files
expand_env_refs || exit 1
resolve_storage_dirs || exit 1
stop_host_processes "$dry" || die "host shutdown incomplete; the data core is left running"
if (( dry )); then ok "dry-run complete; nothing stopped (the data core would keep running)"; exit 0; fi
if (( ${#DATA_SVCS[@]} )) && can_ask "$nqa" && [[ $(docker_state) == ok ]] && data_core_up; then
  if ask_yes "Also stop the database (ctl dev db stop)" n; then
    stop_data_core 0 || die "apps stopped; the data core is left running"
    ok "apps and data core stopped; containers and data preserved"
    exit 0
  fi
fi
if (( ${#DATA_SVCS[@]} )); then ok "apps stopped; the data core is left as it was (ctl dev db stop stops it)"; else ok "apps stopped"; fi
