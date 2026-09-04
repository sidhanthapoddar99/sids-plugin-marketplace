#!/usr/bin/env bash
# db/restore.sh — `ctl db restore <dir>`. Load a `ctl db backup` folder back into the running
# engines. Destructive: postgres is dropped and recreated. Asks first. Refuses while an app
# container (api/engine) is running, because a live writer mid-restore corrupts both.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "db restore" "Load a backup folder back into the data core (asks first)." \
  'db restore <dir> [-y] [-h]' \
"Arguments
  dir             a folder written by ctl db backup

Options
  -y, --yes       skip the confirmation
  -h, --help      show this help

postgres: drop + recreate \$POSTGRES_DB, pg_restore. redis: copy the rdb in, restart redis.
neo4j: replay the schema file. Refuses while api or engine containers are running."; }

is_help "${1:-}" && { usage; exit 0; }
dir="" yes=0
while (( $# )); do case "$1" in -y|--yes) yes=1; shift ;; -*) die "unknown flag $1" ;; *) dir="$1"; shift ;; esac; done
[[ -n $dir && -d $dir ]] || die "usage: ctl db restore <backup dir>"
require_env; require_docker
for svc in api engine; do [[ -n "$(dc ps -q "$svc" 2>/dev/null)" ]] && die "$svc is running — ctl down $svc first"; done
if (( ! yes )); then
  warn "this REPLACES the current data with $dir"
  confirm "continue" || { say "aborted."; exit 0; }
fi
has() { printf '%s\n' "${DATA_SVCS[@]}" | grep -qx "$1"; }
u="${POSTGRES_USER:-postgres}"; db="${POSTGRES_DB:-postgres}"

if has postgres && [[ -f $dir/postgres.dump ]]; then
  step "postgres: drop + recreate $db, pg_restore"
  dc exec -T postgres psql -U "$u" -d postgres -c "DROP DATABASE IF EXISTS \"$db\";" -c "CREATE DATABASE \"$db\";"
  dc exec -T postgres pg_restore -U "$u" -d "$db" --no-owner < "$dir/postgres.dump"
  ok "postgres"
fi
if has redis && [[ -f $dir/redis.rdb ]]; then
  step "redis: load dump.rdb, restart"
  dc stop redis >/dev/null
  docker cp "$dir/redis.rdb" "$(dc ps -aq redis):/data/dump.rdb"
  dc start redis >/dev/null
  ok "redis"
fi
if has neo4j && [[ -f $dir/neo4j-schema.cypher ]]; then
  step "neo4j: replay schema"
  dc exec -T neo4j cypher-shell -u neo4j -p "${NEO4J_PASSWORD:?}" < "$dir/neo4j-schema.cypher"
  ok "neo4j (schema)"
fi
ok "restored from $dir"
