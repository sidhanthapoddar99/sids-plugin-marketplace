#!/usr/bin/env bash
# db/backup.sh — `ctl db backup`. Dump the data core into ${BACKUP_DIR:-data/backups}/<timestamp>/:
# postgres → pg_dump (custom format), redis → SAVE + copy dump.rdb, neo4j → cypher export of the
# constraints/indexes only (a full neo4j dump needs the database stopped — see TODO).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "db backup" "Dump every data engine into a timestamped folder." \
  'db backup [-h]' \
"Options
  -h, --help      show this help

Writes ${BACKUP_DIR:-data/backups}/<YYYYmmdd-HHMMSS>/{postgres.dump, redis.rdb, neo4j-schema.cypher}.
Restore with: ctl db restore <that folder>." \
"TODO: a full neo4j dump (neo4j-admin database dump) needs the container stopped; not automated here."; }

is_help "${1:-}" && { usage; exit 0; }
require_env; require_docker
dest="${BACKUP_DIR:-data/backups}/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$dest"
has() { printf '%s\n' "${DATA_SVCS[@]}" | grep -qx "$1"; }

if has postgres; then
  step "pg_dump → $dest/postgres.dump"
  dc exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -Fc > "$dest/postgres.dump"
  ok "postgres"
fi
if has redis; then
  step "redis SAVE → $dest/redis.rdb"
  dc exec -T redis redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} SAVE >/dev/null
  docker cp "$(dc ps -q redis):/data/dump.rdb" "$dest/redis.rdb"
  ok "redis"
fi
if has neo4j; then
  step "neo4j schema → $dest/neo4j-schema.cypher"
  dc exec -T neo4j cypher-shell -u neo4j -p "${NEO4J_PASSWORD:?}" --format plain "SHOW CONSTRAINTS YIELD createStatement RETURN createStatement" \
    | sed '1d; s/^"//; s/"$//' > "$dest/neo4j-schema.cypher"
  ok "neo4j (schema only)"
fi
ok "backup at $dest ($(du -sh "$dest" | cut -f1))"
