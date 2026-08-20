#!/usr/bin/env bash
# container/health.sh — `ctl health`. One-shot health check of the data core (or named services).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "health" "One-shot health table for the stack's containers." \
  'health [svc…] [-h]' \
"Arguments
  svc…            services to check (default: the data core if set — ${DATA_SVCS[*]:-none} — else all compose services)

Options
  -h, --help      show this help

'healthy' comes from each container's healthcheck; a stopped service shows 'not running'."; }

is_help "${1:-}" && { usage; exit 0; }
require_tools docker
load_env_file .env   # soft, non-clobbering — diagnostics never die, but dc needs ${VAR} interpolation
# default target: the data core, else (no data core) every service the base compose defines
svcs=("$@")
(( ${#svcs[@]} )) || svcs=("${DATA_SVCS[@]}")
(( ${#svcs[@]} )) || mapfile -t svcs < <(dc config --services 2>/dev/null)
step "container health"
health_table "${svcs[@]}"
