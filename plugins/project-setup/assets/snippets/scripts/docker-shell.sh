#!/usr/bin/env bash
# docker-shell.sh — `ctl shell`. Open the right client/shell inside a running service container.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "shell" "Open a shell or DB client inside a running service container." \
  'shell <service> [-h]' \
"Smart targets
  postgres        psql as \$POSTGRES_USER on \$POSTGRES_DB
  redis           redis-cli (authenticated with \$REDIS_PASSWORD if set)
  <other>         an interactive shell (bash, falling back to sh)

Options
  -h, --help      show this help" \
"For an arbitrary one-off command, use: ctl exec <service> <command…>"; }

is_help "${1:-}" && { usage; exit 0; }
[[ $# -ge 1 ]] || die "usage: ctl shell <service>"
require_env
svc="$1"
case "$svc" in
  postgres) dc exec postgres psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" ;;
  redis)    if [[ -n "${REDIS_PASSWORD:-}" ]]; then dc exec redis redis-cli -a "$REDIS_PASSWORD"
            else dc exec redis redis-cli; fi ;;
  *)        dc exec "$svc" bash 2>/dev/null || dc exec "$svc" sh ;;
esac
