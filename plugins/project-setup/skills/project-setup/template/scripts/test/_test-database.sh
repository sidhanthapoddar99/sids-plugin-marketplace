#!/usr/bin/env bash
# test/_test-database.sh — the throwaway PostgreSQL servers one `ctl test` run owns. SOURCE it after
# _lib.sh and _process.sh; test/test.sh is the one caller.
#
# A suite marked `db` in scripts/gate/_targets.sh runs against this run's server, never against the
# dev data core, so a stopped, half-migrated or busy dev database cannot fail it, and two worktrees
# never share test data. A server keeps its data on tmpfs with fsync off, because nothing on it
# outlives the run. The run migrates the database `test_template` once on each server, with the
# project's own migration image, and each db suite gets its own copy, `CREATE DATABASE … TEMPLATE
# test_template`, which takes milliseconds where a migration takes seconds.
#
# Each suite reads DATABASE_URL and TEST_DATABASE_URL (its own database) and the POSTGRES_* parts.
# A suite that wants a clean database per test or per worker clones TEST_DATABASE_TEMPLATE the same
# way. A caller that sets TEST_DATABASE_URL, such as CI with its own PostgreSQL service, gets no
# server: every db suite reads that database as it is, already migrated by the caller.
#
# ONE SERVER PER WORKER. A suite marked `db workers` that runs on more than one pytest worker gets one
# server per worker, and TEST_DATABASE_URLS lists its own database on each, worker gw<n> on entry n.
# Docker Desktop forwards each connection to a published port by opening a new connection from its
# VM to the container. The VM has 10,536 source ports per container address, and a closed connection
# holds its port for 60 s, so one server takes about 175 new connections a second. Studio's eight
# workers opened about 420 a second, and after about 25 s every new connection closed before
# PostgreSQL saw it. Each server has its own address, so each worker gets its own ports.
#
# A suite on several workers reads TEST_DATABASE_URLS only. Its plain settings (DATABASE_URL,
# TEST_DATABASE_URL, POSTGRES_DB) name TEST_DATABASE_UNSET, a database no server has, until its worker
# plugin points them at the worker's own database. A suite without that plugin, or code that reads a
# setting before its worker has a database, then fails on connect instead of sharing one database.

TEST_DATABASE_IDS=() TEST_DATABASE_PORTS=() TEST_DATABASE_PASSWORD="" TEST_DATABASE_LOGS=""
TEST_DATABASE_LABEL=ctl.test-database
TEST_DATABASE_USER=test
TEST_DATABASE_TEMPLATE=test_template
TEST_DATABASE_UNSET=test_worker_database_not_set
TEST_DATABASE_WAIT=${TEST_DATABASE_WAIT:-60}   # seconds the servers may take to accept connections

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

# test_database_sql <server> <database> <statement> — run one statement as the superuser of server
# <server>, counted from 0.
test_database_sql() {
  docker exec "${TEST_DATABASE_IDS[$1]}" psql -q -v ON_ERROR_STOP=1 -U "$TEST_DATABASE_USER" -d "$2" -c "$3" >/dev/null
}

# test_database_flyway <image> <server> — migrate test_template on one server. Flyway joins the
# server's own network, so it reaches the server whatever runtime runs Docker.
test_database_flyway() {
  docker run --rm --network "container:${TEST_DATABASE_IDS[$2]}" \
    -e FLYWAY_URL="jdbc:postgresql://127.0.0.1:5432/$TEST_DATABASE_TEMPLATE" \
    -e FLYWAY_USER="$TEST_DATABASE_USER" -e FLYWAY_PASSWORD="$TEST_DATABASE_PASSWORD" "$1" migrate
}

# test_database_migrate <image> — migrate test_template on every server. One server shows its
# output as it runs. Several migrate at once, each into its own file in TEST_DATABASE_LOGS, because
# interleaved logs cannot be read; a failed one prints its file whole.
test_database_migrate() {
  local image="$1" index rc=0 pids=()
  (( ${#TEST_DATABASE_IDS[@]} > 1 )) || { test_database_flyway "$image" 0; return; }
  for index in "${!TEST_DATABASE_IDS[@]}"; do
    test_database_flyway "$image" "$index" > "$TEST_DATABASE_LOGS/migrate-$index.log" 2>&1 & pids+=("$!")
  done
  for index in "${!pids[@]}"; do
    wait "${pids[$index]}" && continue
    rc=1; err "the migrations failed on test database server $index:"; cat "$TEST_DATABASE_LOGS/migrate-$index.log" >&2
  done
  return $rc
}

# test_database_start [servers] — start the servers, 1 when not given, wait until each accepts
# connections, and migrate test_template on each. Dies by name on failure, and removes every server
# first. Docker picks each loopback port; host suites reach it, and Flyway joins the server's network.
test_database_start() {
  local servers="${1:-1}" image migrate birth deadline index id port
  require_docker; require_tools jq
  image=$(test_database_image postgres) || die "compose names no postgres image yet (a <version> placeholder?) — the test database runs the image the data core runs"
  migrate=$(test_database_image migrate) || die "compose names no migrate image — the test database is migrated with the project's own migration image"
  birth=$(process_identity "$$") || die "cannot read this run's process identity for the test database"
  test_database_sweep
  TEST_DATABASE_PASSWORD=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
  # Several servers log their migrations and copies here; test_database_stop removes it with them.
  (( servers == 1 )) || TEST_DATABASE_LOGS=$(mktemp -d) || die "cannot create a folder for the test database logs"
  if (( servers == 1 )); then step "starting this run's own PostgreSQL ($image, on tmpfs)"
  else step "starting this run's own PostgreSQL ($image, on tmpfs): $servers servers, one per db test worker"; fi
  for (( index = 0; index < servers; index++ )); do
    id=$(docker run -d --rm --label "$TEST_DATABASE_LABEL.root=$CTL_ROOT" \
      --label "$TEST_DATABASE_LABEL.owner=$$:$birth" \
      --tmpfs /var/lib/postgresql:rw,size=2g --shm-size 256m --memory 3g \
      -e POSTGRES_USER="$TEST_DATABASE_USER" -e POSTGRES_PASSWORD="$TEST_DATABASE_PASSWORD" \
      -e POSTGRES_DB="$TEST_DATABASE_TEMPLATE" -e POSTGRES_INITDB_ARGS="--encoding=UTF-8 --locale=C.UTF-8" \
      -p 127.0.0.1::5432 "$image" -c fsync=off -c synchronous_commit=off -c full_page_writes=off) \
      || { test_database_stop; die "could not start the test database from $image"; }
    TEST_DATABASE_IDS+=("$id")
  done
  for id in "${TEST_DATABASE_IDS[@]}"; do
    port=$(docker port "$id" 5432/tcp | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' | head -1)
    [[ -n $port ]] || { test_database_stop; die "cannot read the test database's loopback port"; }
    TEST_DATABASE_PORTS+=("$port")
  done
  # The image runs initdb on a socket only, then restarts on TCP, so a TCP probe sees the final server.
  deadline=$((SECONDS + TEST_DATABASE_WAIT))
  for id in "${TEST_DATABASE_IDS[@]}"; do
    until docker exec "$id" pg_isready -q -h 127.0.0.1 -U "$TEST_DATABASE_USER" -d "$TEST_DATABASE_TEMPLATE" 2>/dev/null; do
      (( SECONDS < deadline )) || { test_database_stop; die "the test database did not accept connections within $TEST_DATABASE_WAIT s"; }
      sleep 0.2
    done
  done
  if (( servers == 1 )); then step "migrating $TEST_DATABASE_TEMPLATE once ($migrate)"
  else step "migrating $TEST_DATABASE_TEMPLATE on each server at once ($migrate)"; fi
  dc_build migrate >&2 || { test_database_stop; die "the migration image did not build"; }
  test_database_migrate "$migrate" \
    || { test_database_stop; die "the migrations failed on the test database — see the Flyway output above"; }
  if (( servers == 1 )); then ok "test database ready on 127.0.0.1:${TEST_DATABASE_PORTS[0]}, $TEST_DATABASE_TEMPLATE migrated"
  else ok "$servers test database servers ready on 127.0.0.1:${TEST_DATABASE_PORTS[*]}, $TEST_DATABASE_TEMPLATE migrated on each"; fi
}

# test_database_copy <server> <database> — a fresh copy of test_template named <database> on one server
test_database_copy() {
  test_database_sql "$1" postgres "DROP DATABASE IF EXISTS \"$2\"" \
    && test_database_sql "$1" postgres "CREATE DATABASE \"$2\" TEMPLATE $TEST_DATABASE_TEMPLATE"
}

# test_database_for <suite> [servers] — create the suite's own copy of test_template on the first
# <servers> servers, 1 when not given, and print the settings the suite reads, one NAME=value per
# line, for `env`. With one server, the plain settings name the copy. With several,
# TEST_DATABASE_URLS lists the copy on each, separated by spaces, in server order, and the plain
# settings name TEST_DATABASE_UNSET on the first server, which the worker plugin replaces.
test_database_for() {
  local name="test_${1//[^a-z0-9]/_}" servers="${2:-1}" plain index rc=0 pids=() urls=()
  (( servers <= ${#TEST_DATABASE_IDS[@]} )) || die "the $1 suite wants $servers test database servers, and this run started ${#TEST_DATABASE_IDS[@]}"
  if (( servers == 1 )); then test_database_copy 0 "$name" || rc=1
  else
    # Each server's psql notices go to its own file, printed only when that copy fails.
    for (( index = 0; index < servers; index++ )); do
      test_database_copy "$index" "$name" > "$TEST_DATABASE_LOGS/copy-$name-$index.log" 2>&1 & pids+=("$!")
    done
    for index in "${!pids[@]}"; do
      wait "${pids[$index]}" && continue
      rc=1; err "the copy for the $1 suite failed on test database server $index:"; cat "$TEST_DATABASE_LOGS/copy-$name-$index.log" >&2
    done
  fi
  (( rc == 0 )) || die "could not copy $TEST_DATABASE_TEMPLATE for the $1 suite"
  for (( index = 0; index < servers; index++ )); do
    urls+=("postgresql://$TEST_DATABASE_USER:$TEST_DATABASE_PASSWORD@127.0.0.1:${TEST_DATABASE_PORTS[index]}/$name")
  done
  plain=$name; (( servers == 1 )) || plain=$TEST_DATABASE_UNSET
  printf '%s\n' "DATABASE_URL=${urls[0]%/*}/$plain" "TEST_DATABASE_URL=${urls[0]%/*}/$plain" "TEST_DATABASE_TEMPLATE=$TEST_DATABASE_TEMPLATE" \
    "POSTGRES_HOST=127.0.0.1" "POSTGRES_PORT=${TEST_DATABASE_PORTS[0]}" "POSTGRES_USER=$TEST_DATABASE_USER" \
    "POSTGRES_PASSWORD=$TEST_DATABASE_PASSWORD" "POSTGRES_DB=$plain"
  (( servers == 1 )) || printf '%s\n' "TEST_DATABASE_URLS=${urls[*]}"
}

# test_database_stop — remove every server and everything on it, in one docker call, and the logs.
test_database_stop() {
  [[ -z $TEST_DATABASE_LOGS ]] || { rm -rf "$TEST_DATABASE_LOGS"; TEST_DATABASE_LOGS=""; }
  (( ${#TEST_DATABASE_IDS[@]} )) || return 0
  docker rm -f "${TEST_DATABASE_IDS[@]}" >/dev/null 2>&1 || warn "could not remove the test database container(s) ${TEST_DATABASE_IDS[*]}"
  TEST_DATABASE_IDS=() TEST_DATABASE_PORTS=()
}
