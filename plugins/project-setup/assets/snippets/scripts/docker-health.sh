#!/usr/bin/env bash
# docker-health.sh — `ctl health`. One-shot health check of the data core (or named services).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "health" "One-shot health check of the data core (or named services)." \
  'health [svc…] [-h]' \
"Arguments
  svc…            services to check (default: the data core — ${DATA_SVCS[*]})

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
svcs=("$@"); (( ${#svcs[@]} )) || svcs=("${DATA_SVCS[@]}")
step "container health"
health_table "${svcs[@]}"
