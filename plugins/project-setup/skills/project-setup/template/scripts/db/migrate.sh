#!/usr/bin/env bash
# db/migrate.sh — `ctl migrate`. The only path that touches schema. Postgres: Alembic in
# apps/database/postgres (hand-written revisions: .py shim + .up.sql/.down.sql). Neo4j:
# apps/database/neo4j/init.cypher, idempotent, applied through the container's cypher-shell.
# Runs against .env values on the host (ctl dev) or the same values under ctl up.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

PG_DIR="apps/database/postgres"
NEO4J_INIT="apps/database/neo4j/init.cypher"

usage() { print_help "migrate" "Apply schema migrations (Alembic + neo4j init). The only path that touches schema." \
  'migrate [up|down|new "<msg>"|status] [-h]' \
"Commands
  up (default)    alembic upgrade head, then apply $NEO4J_INIT
  down            alembic downgrade -1
  new \"<msg>\"      create a revision: the .py shim + empty .up.sql / .down.sql siblings
  status          alembic current + heads

Options
  -h, --help      show this help" \
"Never run alembic by hand. Migrations run as an explicit step, never on app boot."; }

is_help "${1:-}" && { usage; exit 0; }
require_env
sub="${1:-up}"; shift || true

pg()    { ( cd "$PG_DIR" && uv run alembic "$@" ); }
neo4j() {
  [[ -f $NEO4J_INIT ]] || { say "${C_DIM}no $NEO4J_INIT — skipped${C_RESET}"; return 0; }
  printf '%s\n' "${DATA_SVCS[@]}" | grep -qx neo4j || return 0
  step "neo4j: cypher-shell < $NEO4J_INIT"
  dc exec -T neo4j cypher-shell -u neo4j -p "${NEO4J_PASSWORD:?NEO4J_PASSWORD blank in .env}" < "$NEO4J_INIT"
}

case "$sub" in
  up)     step "alembic upgrade head";  pg upgrade head; neo4j ;;
  down)   step "alembic downgrade -1";  pg downgrade -1 ;;
  status) pg current; pg heads ;;
  new)
    [[ -n "${1:-}" ]] || die 'usage: ctl migrate new "<message>"'
    step "alembic revision: $1"
    out=$(pg revision -m "$1" | tee /dev/stderr)
    # the mako template emits the .py shim; create the empty SQL siblings it loads.
    revfile=$(grep -oE "$PG_DIR/migrations/versions/[^ ]+\.py" <<<"$out" | head -n1 || true)
    if [[ -n "$revfile" ]]; then
      base="${revfile%.py}"; : > "${base}.up.sql"; : > "${base}.down.sql"
      ok "created:"; printf '    %s\n' "$revfile" "${base}.up.sql" "${base}.down.sql"
      say "${C_DIM}Write DDL in the .up.sql; .down.sql may stay empty for forward-only migrations.${C_RESET}"
    else warn "could not locate the new revision file — check $PG_DIR/migrations/versions/"; fi ;;
  -*)     usage; exit 1 ;;
  *)      die "unknown migrate subcommand: $sub (try ctl migrate --help)" ;;
esac
ok "migrate $sub done"
