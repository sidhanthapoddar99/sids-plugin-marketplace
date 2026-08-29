#!/usr/bin/env bash
# db/shell.sh — `ctl db shell <engine>`. The right client inside the running engine container,
# authenticated from .env. Works under ctl dev and ctl up alike (the engines are containers in both).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "db shell" "Interactive client for one data engine, with .env credentials." \
  'db shell <postgres|redis|neo4j> [-h]' \
"Targets
  postgres        psql as \$POSTGRES_USER on \$POSTGRES_DB
  redis           redis-cli, authenticated with \$REDIS_PASSWORD
  neo4j           cypher-shell as neo4j with \$NEO4J_PASSWORD

Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
[[ $# -ge 1 ]] || die "usage: ctl db shell <postgres|redis|neo4j>"
require_env
case "$1" in
  postgres) dc exec postgres psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" ;;
  redis)    dc exec redis redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} ;;
  neo4j)    dc exec neo4j cypher-shell -u neo4j -p "${NEO4J_PASSWORD:?NEO4J_PASSWORD blank in .env}" ;;
  *)        die "unknown engine '$1' — postgres | redis | neo4j" ;;
esac
