#!/usr/bin/env bash
# test/_test-database.sh — the throwaway PostgreSQL one `ctl test` run owns. SOURCE it after
# _lib.sh and _process.sh; test/test.sh is the one caller.
#
# A suite marked `db` in scripts/gate/_targets.sh runs against this server, never against the dev
# data core, so a stopped, half-migrated or busy dev database cannot fail it, and two worktrees
# never share test data. The server keeps its data on tmpfs with fsync off, because nothing on it
# outlives the run. The run migrates the database `test_template` once, with the project's own
# migration image, and each db suite gets its own copy, `CREATE DATABASE … TEMPLATE test_template`,
# which takes milliseconds where a migration takes seconds.
#
# Each suite reads DATABASE_URL and TEST_DATABASE_URL (its own database) and the POSTGRES_* parts.
# A suite that wants a clean database per test or per worker clones TEST_DATABASE_TEMPLATE the same
# way. A caller that sets TEST_DATABASE_URL, such as CI with its own PostgreSQL service, gets no
# server: every db suite reads that database as it is, already migrated by the caller.

TEST_DATABASE_ID="" TEST_DATABASE_PORT="" TEST_DATABASE_PASSWORD=""
TEST_DATABASE_LABEL=ctl.test-database
TEST_DATABASE_USER=test
TEST_DATABASE_TEMPLATE=test_template
TEST_DATABASE_WAIT=${TEST_DATABASE_WAIT:-60}   # seconds the server may take to accept connections

# test_database_image <service> — the image compose gives <service>, so the tests run the engine
# version production runs and the migrations production applies.
test_database_image() {
  local image
  image=$(dc config --format json | jq -r --arg s "$1" '.services[$s].image // empty') || return 1
  [[ -n $image && $image != *'<'* ]] || return 1
  printf '%s\n' "$image"
}

# test_database_sweep — remove this checkout's test servers whose run is gone, such as one a killed
# run left behind. A server whose run still lives is kept, because that run may be using it.
test_database_sweep() {
  local id owner pid birth
  while read -r id owner; do
    [[ -n $id ]] || continue
    pid=${owner%%:*} birth=${owner#*:}
    [[ -n $birth && $(process_identity "$pid" 2>/dev/null) == "$birth" ]] && continue
    docker rm -f "$id" >/dev/null 2>&1 || warn "could not remove the leftover test database container $id"
  done < <(docker ps -a --filter "label=$TEST_DATABASE_LABEL.root=$CTL_ROOT" \
    --format "{{.ID}} {{.Label \"$TEST_DATABASE_LABEL.owner\"}}" 2>/dev/null)
}

# test_database_sql <database> <statement> — run one statement as the server's superuser.
test_database_sql() {
  docker exec "$TEST_DATABASE_ID" psql -q -v ON_ERROR_STOP=1 -U "$TEST_DATABASE_USER" -d "$1" -c "$2" >/dev/null
}

# test_database_start — start the server, wait until it accepts connections, and migrate
# test_template once. Dies by name on failure, and removes the server first.
test_database_start() {
  local image migrate birth deadline
  require_docker; require_tools jq
  image=$(test_database_image postgres) || die "compose names no postgres image yet (a <version> placeholder?) — the test database runs the image the data core runs"
  migrate=$(test_database_image migrate) || die "compose names no migrate image — the test database is migrated with the project's own migration image"
  birth=$(process_identity "$$") || die "cannot read this run's process identity for the test database"
  test_database_sweep
  TEST_DATABASE_PASSWORD=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
  step "starting this run's own PostgreSQL ($image, on tmpfs)"
  # Docker picks a free loopback port. Host suites reach it; Flyway below joins the server's network.
  TEST_DATABASE_ID=$(docker run -d --rm --label "$TEST_DATABASE_LABEL.root=$CTL_ROOT" \
    --label "$TEST_DATABASE_LABEL.owner=$$:$birth" \
    --tmpfs /var/lib/postgresql:rw,size=2g --shm-size 256m --memory 3g \
    -e POSTGRES_USER="$TEST_DATABASE_USER" -e POSTGRES_PASSWORD="$TEST_DATABASE_PASSWORD" \
    -e POSTGRES_DB="$TEST_DATABASE_TEMPLATE" -e POSTGRES_INITDB_ARGS="--encoding=UTF-8 --locale=C.UTF-8" \
    -p 127.0.0.1::5432 "$image" -c fsync=off -c synchronous_commit=off -c full_page_writes=off) \
    || die "could not start the test database from $image"
  TEST_DATABASE_PORT=$(docker port "$TEST_DATABASE_ID" 5432/tcp | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' | head -1)
  [[ -n $TEST_DATABASE_PORT ]] || { test_database_stop; die "cannot read the test database's loopback port"; }
  # The image runs initdb on a socket only, then restarts on TCP, so a TCP probe sees the final server.
  deadline=$((SECONDS + TEST_DATABASE_WAIT))
  until docker exec "$TEST_DATABASE_ID" pg_isready -q -h 127.0.0.1 -U "$TEST_DATABASE_USER" -d "$TEST_DATABASE_TEMPLATE" 2>/dev/null; do
    (( SECONDS < deadline )) || { test_database_stop; die "the test database did not accept connections within $TEST_DATABASE_WAIT s"; }
    sleep 0.2
  done
  step "migrating $TEST_DATABASE_TEMPLATE once ($migrate)"
  dc build migrate >&2 || { test_database_stop; die "the migration image did not build"; }
  # Flyway joins the server's own network, so it reaches the server whatever runtime runs Docker.
  docker run --rm --network "container:$TEST_DATABASE_ID" \
    -e FLYWAY_URL="jdbc:postgresql://127.0.0.1:5432/$TEST_DATABASE_TEMPLATE" \
    -e FLYWAY_USER="$TEST_DATABASE_USER" -e FLYWAY_PASSWORD="$TEST_DATABASE_PASSWORD" "$migrate" migrate \
    || { test_database_stop; die "the migrations failed on the test database — see the Flyway output above"; }
  ok "test database ready on 127.0.0.1:$TEST_DATABASE_PORT, $TEST_DATABASE_TEMPLATE migrated"
}

# test_database_for <suite> — create the suite's own copy of test_template and print the settings
# the suite reads, one NAME=value per line, for `env`.
test_database_for() {
  local name="test_${1//[^a-z0-9]/_}" url
  test_database_sql postgres "DROP DATABASE IF EXISTS \"$name\"" \
    && test_database_sql postgres "CREATE DATABASE \"$name\" TEMPLATE $TEST_DATABASE_TEMPLATE" \
    || die "could not copy $TEST_DATABASE_TEMPLATE for the $1 suite"
  url="postgresql://$TEST_DATABASE_USER:$TEST_DATABASE_PASSWORD@127.0.0.1:$TEST_DATABASE_PORT/$name"
  printf '%s\n' "DATABASE_URL=$url" "TEST_DATABASE_URL=$url" "TEST_DATABASE_TEMPLATE=$TEST_DATABASE_TEMPLATE" \
    "POSTGRES_HOST=127.0.0.1" "POSTGRES_PORT=$TEST_DATABASE_PORT" "POSTGRES_USER=$TEST_DATABASE_USER" \
    "POSTGRES_PASSWORD=$TEST_DATABASE_PASSWORD" "POSTGRES_DB=$name"
}

# test_database_stop — remove the server and everything on it.
test_database_stop() {
  [[ -n $TEST_DATABASE_ID ]] || return 0
  docker rm -f "$TEST_DATABASE_ID" >/dev/null 2>&1 || warn "could not remove the test database container $TEST_DATABASE_ID"
  TEST_DATABASE_ID=""
}
