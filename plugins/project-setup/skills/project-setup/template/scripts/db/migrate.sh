#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
flyway_new() {
  local message="$1" slug version directory file
  slug=$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g')
  [[ -n $slug ]] || die 'migration description must contain letters or digits'
  version=$(date -u +%Y%m%d%H%M%S)
  directory="$CTL_ROOT/apps/database/postgres/migrations"
  mkdir -p "$directory"
  compgen -G "$directory/V${version}__*.sql" >/dev/null && die 'a migration already uses this timestamp; retry in one second'
  file="$directory/V${version}__${slug}.sql"
  (set -o noclobber; printf -- '-- %s\n-- Add forward migration SQL here. Do not edit after application.\n' "$slug" > "$file") || return 1
  ok "created $file"
}
FLYWAY_SERVICE=migrate
usage() { print_help 'db migrate' 'Flyway PostgreSQL migrations.' \
  'db migrate [up|status|check|new "description"] [-h]' \
"Commands
  up (default)    validate and apply pending SQL migrations
  status          show Flyway migration history and pending files
  check           verify applied migrations match the current checkout
  new description create a timestamped SQL migration without contacting the database

Options
  -h, --help      show this help

Flyway runs in the Compose migration container and connects to PostgreSQL inside Docker.
Production uses the same migration image before starting apps. Changes are forward-only; create a new migration
to reverse an earlier change. This command never resets a database."; }
for arg in "$@"; do is_help "$arg" && { usage; exit 0; }; done
mode=up; positional=()
for arg in "$@"; do
  case "$arg" in -*) die "unknown flag: $arg";; *) positional+=("$arg");; esac
done
if (( ${#positional[@]} )); then mode=${positional[0]}; fi
if [[ $mode == new ]]; then
  (( ${#positional[@]} == 2 )) || die 'usage: ctl db migrate new "description"'
  flyway_new "${positional[1]}"
  exit 0
fi
(( ${#positional[@]} <= 1 )) || die "db migrate $mode takes no extra arguments"
case "$mode" in up|status|check) ;; down) die 'Migrations are forward-only; create a new migration to reverse a change';; *) die "unknown migrate command: $mode";; esac
require_env; require_docker
services=$(dc ps --status running --services) || die 'cannot inspect this project database services'
printf '%s\n' "$services" | grep -qx postgres || die 'PostgreSQL is not running for this project; start the data stack first'
pg() {
  local argv=() tty=()
  # Keep build output separate from Flyway machine-readable results.
  dc build "$FLYWAY_SERVICE" >&2
  [[ -t 0 && -t 1 ]] || tty=(-T)
  mapfile -t argv < <(compose_argv -f "$BASE" run --rm --no-deps "${tty[@]}" "$FLYWAY_SERVICE" "$@")
  "${argv[@]}"
}
case "$mode" in
  up) pg migrate ;;
  status) pg info ;;
  check)
    require_tools jq
    report=$(pg -outputType=json -ignoreMigrationPatterns= validate)
    printf '%s\n' "$report" | jq -e '.validationSuccessful == true and .validateCount > 0' >/dev/null \
      || die 'database migrations are pending or invalid; inspect ctl db migrate status'
    ok 'database migrations are current' ;;
esac

# Non-relational storage keeps its own initializer; Flyway handles PostgreSQL only.
if [[ $mode == up && -f apps/database/neo4j/init.cypher && " ${DATA_SVCS[*]} " == *" neo4j "* ]]; then
  source "$CTL_ROOT/scripts/common/_runtime.sh"
  runtime_run neo4j-init
fi
