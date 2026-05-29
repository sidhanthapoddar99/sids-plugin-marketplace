#!/usr/bin/env bash
# dev-migrate.sh — `ctl migrate`. Alembic migrations (the backend owns DDL).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "migrate" "Run database migrations (Alembic)." \
  'migrate {up|down|new "<msg>"|status} [-h]' \
"Commands
  up              upgrade to head
  down            downgrade one revision
  new \"<msg>\"      create a new revision
  status          show the current revision

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
require_env

sub="${1:-}"; shift || true
case "$sub" in
  up)     step "alembic upgrade head";    ( cd apps/backend && uv run alembic upgrade head ) ;;
  down)   step "alembic downgrade -1";    ( cd apps/backend && uv run alembic downgrade -1 ) ;;
  new)    [[ -n "${1:-}" ]] || die 'usage: ctl migrate new "<message>"'
          step "alembic revision: $1";    ( cd apps/backend && uv run alembic revision -m "$1" ) ;;
  status) ( cd apps/backend && uv run alembic current ) ;;
  ''|-*)  usage; exit 1 ;;
  *)      die "unknown migrate subcommand: $sub (try ctl migrate --help)" ;;
esac
ok "migrate $sub done"
