#!/usr/bin/env bash
# container/shell.sh — `ctl shell <svc>`. An interactive shell inside a running service container.
# DB clients (psql, redis-cli, cypher-shell) are `ctl db shell <engine>`.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "shell" "Open a shell inside a running service container." \
  'shell <service> [-h]' \
"Arguments
  service         the compose service (api, engine, web, site, nginx, …)

Options
  -h, --help      show this help" \
"bash when the image has it, else sh. One-off commands: ctl exec <service> <command…>.
Database clients: ctl db shell <postgres|redis|neo4j>."; }

is_help "${1:-}" && { usage; exit 0; }
[[ $# -ge 1 ]] || die "usage: ctl shell <service>"
require_env
dc exec "$1" bash 2>/dev/null || dc exec "$1" sh
