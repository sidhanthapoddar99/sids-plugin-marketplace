#!/usr/bin/env bash
# db/restore.sh — `ctl db restore <dir>`. Load a `ctl db backup` folder back into the running
# engines. Destructive: postgres is dropped and recreated. Asks first. Refuses while an app
# container (api/engine) is running, because a live writer mid-restore corrupts both.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/common/_runtime.sh"
source "$CTL_ROOT/scripts/common/_paths.sh"
source "$CTL_ROOT/scripts/common/_process.sh"

RESTORE_DEPENDENTS=(api engine)

usage() { print_help "db restore" "Load a backup folder back into the data core (asks first)." \
  'db restore <dir> [-y] [-h]' \
"Arguments
  dir             a folder written by ctl db backup; relative paths start at the project root

Options
  -y, --yes       skip the confirmation
  -h, --help      show this help

postgres: drop + recreate \$POSTGRES_DB, pg_restore. redis: copy the rdb in, restart redis.
neo4j: replay the schema file. Refuses while api or engine containers or recorded host dev PIDs run.
Requires a readable PostgreSQL custom archive when postgres is enabled. Checks its header and
pg_restore --list before changing any engine; listing does not prove a full restore will succeed."; }

is_help "${1:-}" && { usage; exit 0; }
dir="" yes=0
while (( $# )); do case "$1" in -y|--yes) yes=1; shift ;; -*) die "unknown flag $1" ;; *) [[ -z $dir ]] || die "expected one backup directory"; dir="$1"; shift ;; esac; done
[[ -n $dir && -d $dir ]] || die "usage: ctl db restore <backup dir>"
require_env; require_docker
resolve_storage_dirs
running=$(runtime_running_services) || die "cannot query running services in the current Compose project"
for svc in "${RESTORE_DEPENDENTS[@]}"; do
  if grep -Fxq -- "$svc" <<< "$running"; then die "$svc is running — ctl down $svc first"; fi
done
for pidfile in "$LOGS_DIR"/run/*.pid; do
  [[ -f $pidfile ]] || continue
  pid=$(cat -- "$pidfile")
  if [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
    die "host dev process $pid is running ($pidfile) — stop it before restoring"
  fi
done
for record in "$LOGS_DIR"/run/*.process; do
  if process_running "$record"; then die "host dev process is running ($record) — stop it before restoring"; fi
done
has() { printf '%s\n' "${DATA_SVCS[@]}" | grep -qx "$1"; }
u="${POSTGRES_USER:-postgres}"; db="${POSTGRES_DB:-postgres}"
if has postgres; then
  archive="$dir/postgres.dump"
  [[ -f $archive && -r $archive ]] || die "missing or unreadable PostgreSQL archive: $archive"
  [[ "$(head -c 5 -- "$archive")" == PGDMP ]] || die "expected pg_dump custom format: $archive"
  dc exec -T postgres pg_restore --list < "$archive" > /dev/null
fi
if (( ! yes )); then
  warn "this REPLACES the current data with $dir"
  confirm "continue" || { say "aborted."; exit 0; }
fi
if has postgres; then
  step "postgres: drop + recreate $db, pg_restore"
  dc exec -T postgres dropdb -U "$u" --if-exists -- "$db"
  dc exec -T postgres createdb -U "$u" -- "$db"
  dc exec -T postgres pg_restore -U "$u" -d "$db" --no-owner < "$dir/postgres.dump"
  ok "postgres"
fi
if has redis && [[ -f $dir/redis.rdb ]]; then
  step "redis: load dump.rdb, restart"
  redis_id=$(dc ps -aq redis)
  [[ -n $redis_id && $redis_id != *$'\n'* ]] || die "expected one Redis container in the current Compose project"
  dc stop redis >/dev/null
  docker cp "$dir/redis.rdb" "$redis_id:/data/dump.rdb"
  dc start redis >/dev/null
  ok "redis"
fi
if has neo4j && [[ -f $dir/neo4j-schema.cypher ]]; then
  step "neo4j: replay schema"
  dc exec -T neo4j cypher-shell -u neo4j -p "${NEO4J_PASSWORD:?}" < "$dir/neo4j-schema.cypher"
  ok "neo4j (schema)"
fi
ok "restored from $dir"
