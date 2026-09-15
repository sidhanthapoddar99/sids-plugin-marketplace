#!/usr/bin/env bash
# db/migrate.sh — `ctl db migrate`. The only path that touches schema. It runs the two one-shot
# services compose.db.yaml defines, inside the compose network, so no engine port is published:
#   migrate      Alembic in apps/database/postgres (hand-written revisions: .py shim + .up.sql/.down.sql),
#                bind-mounted at /work so `new` writes the revision back into the checkout
#   neo4j-init   apps/database/neo4j/init.cypher, idempotent, through the image's cypher-shell
# The same services run on their own whenever the db config comes up (`ctl dev`, `ctl up`), because
# the apps wait on them. This verb re-runs them by name, and owns `new`, `status` and `down`.
# `--no-deps`: the engines must already be up. Letting `run` start them would recreate a container
# whose file set differs (ctl dev binds loopback ports, ctl up does not) under a live stack.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/common/_runtime.sh"

PG_DIR="apps/database/postgres"
NEO4J_INIT="apps/database/neo4j/init.cypher"

usage() { print_help "db migrate" "Apply schema migrations (Alembic + neo4j init), inside the compose network." \
  'db migrate [up|down|new "<msg>"|status] [-h]' \
"Commands
  up (default)    alembic upgrade head, then apply $NEO4J_INIT
  down            alembic downgrade -1
  new \"<msg>\"      create a revision: the .py shim + empty .up.sql / .down.sql siblings
  status          alembic current + heads

Options
  -h, --help      show this help

Needs the data core up: ctl dev, or ctl up preset dev. Runs the migrate / neo4j-init one-shots
from compose.db.yaml with \`docker compose run --rm --no-deps\`." \
"Never run alembic by hand. The apps never migrate on boot: they wait on these one-shots."; }

is_help "${1:-}" && { usage; exit 0; }
require_env; require_docker
sub="${1:-up}"; shift || true

has_svc() { printf '%s\n' "${DATA_SVCS[@]}" | grep -qx "$1"; }
runtime_service_running postgres || die "postgres is not up — run ctl dev, or ctl up preset dev, then retry"
# pg <alembic args…> — one migrate container, fresh image, gone afterwards
pg()    { runtime_run --build migrate alembic "$@"; }
neo4j() {
  [[ -f $NEO4J_INIT ]] || { say "${C_DIM}no $NEO4J_INIT — skipped${C_RESET}"; return 0; }
  has_svc neo4j || return 0
  step "neo4j-init: cypher-shell -f $NEO4J_INIT"
  runtime_run neo4j-init
}

case "$sub" in
  up)     step "migrate: alembic upgrade head";  pg upgrade head; neo4j ;;
  down)   step "migrate: alembic downgrade -1";  pg downgrade -1 ;;
  status) pg current; pg heads ;;
  new)
    [[ -n "${1:-}" ]] || die 'usage: ctl db migrate new "<message>"'
    step "alembic revision: $1"
    # --user: the container writes into the bind mount; without it the revision files come back root-owned
    out=$(runtime_run --build --user "$(id -u):$(id -g)" migrate alembic revision -m "$1" | tee /dev/stderr)
    # the mako template emits the .py shim at /work/… inside the container; map it back to the checkout
    # and create the empty SQL siblings it loads.
    revfile=$(grep -oE "/work/migrations/versions/[^ ]+\.py" <<<"$out" | head -n1 || true)
    if [[ -n "$revfile" ]]; then
      revfile="$PG_DIR${revfile#/work}"
      base="${revfile%.py}"; : > "${base}.up.sql"; : > "${base}.down.sql"
      ok "created:"; printf '    %s\n' "$revfile" "${base}.up.sql" "${base}.down.sql"
      say "${C_DIM}Write DDL in the .up.sql; .down.sql may stay empty for forward-only migrations.${C_RESET}"
    else warn "could not locate the new revision file — check $PG_DIR/migrations/versions/"; fi ;;
  -*)     usage; exit 1 ;;
  *)      die "unknown migrate subcommand: $sub (try ctl db migrate --help)" ;;
esac
ok "db migrate $sub done"
