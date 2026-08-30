# Backend — how a backend is built

The language is chosen in `04_stack.md`; the env contract is `02_env.md`; routing is `03_routing.md`. This page is the inside: the layout by size, domain slices, serving, migrations, the engines. Template: `template/apps/example-api-python/`, `template/apps/example-engine-rust/`, `template/apps/database/`.

## Every backend has

| Piece | Rule |
|---|---|
| One config loader | `config.py` / `config.rs` / `config.go`. Nothing else reads the environment or a file. `02_env.md`. |
| `/health` and `/ready` | Liveness: the process is alive; failing means restart. Readiness: dependencies reachable, migrations applied; failing means pull from the load balancer, not restart. Two endpoints, two actions. |
| Its own prefix | `<PIECE>_HOST/_PORT/_PREFIX` in `.env.proxy`; it binds `_PORT` and mounts `_PREFIX`. |
| Rate limiting at the router | Keyed on the user or API key, never the raw IP for authenticated routes. `07_security.md`. |
| `X-Forwarded-*` trusted from the edge only | Never CORS middleware for our own frontend. |
| Its own image | Non-root user, multi-stage, pinned base, no dev deps in the runtime stage, no `COPY .env*`. |
| Its own suite | `tests/` beside `app/`; structure tests in `tests/conformance/`. `10_testing.md`. |

## Layout by size

Code layout grows with the number of domains. Promote when the second consumer appears, never before.

| Size | Shape |
|---|---|
| A few endpoints | Flat `app/`: `main.py`, `config.py`, `db.py`, `routes.py`, `models.py`. |
| Several domains — the normal backend | Domain slices: `app/<domain>/{models,repository,service,router}.py`, plus `app/core/` for cross-cutting (security, redis, rate limit), `app/health/`, and `main.py` to compose. |
| Layers reused by more than one binary, or compiled apart (Rust) | A cargo workspace, one crate per layer: `common` (config, errors), `data` (every query), `auth`, and a thin `api` binary with one handler module per domain. `api → auth, data → common`. `rust-toolchain.toml` is the real pin. |
| Go CLI | `cmd/<name>/main.go`, `internal/{config,client,ui}/`. |

Python lives in `app/`, never `src/`; a run service sets `[tool.uv] package = false` and pytest `pythonpath = ["."]`. A distributable library is `src/<pkg>/` with `pythonpath = ["src"]`.

## Domain slices

| Rule | Detail |
|---|---|
| The layers | `router` parses, authorises, calls, serialises. `service` holds the rule and is the domain's only public surface. `repository` runs the query, given a connection; the caller owns the transaction. `models` are the request/response types, the source `@scope/types` is generated from. |
| Inside a slice | `router → service → repository`. Never backwards. |
| Across slices | `service → service` only. A domain never touches another domain's `repository` or imports its `models` to reuse a shape: duplicate the DTO. |
| Domain names | Nouns of ownership, never activities and never UI navigation labels. `catalog/`, `orders/`, `access/`; not `build/`, `sync/`, `ingest/`. Test: an activity says what the code does this quarter; an ownership noun says what it is responsible for permanently. A pipeline that builds a catalog lives in `catalog/`. |
| Domains ≠ navigation | The UI groups by workflow; the backend by ownership. Two nav groups may map to one domain. The mapping is a recorded decision in `AGENTS.md`, never an implicit mirror. |
| Ambiguous placement | A `dashboard` that aggregates everything, an `images` feature two domains use: put it somewhere defensible and record the one-line why. |
| Domain-shared code | At the domain root (`app/<domain>/`), not in `core/`. `core/` is for code every domain uses. Code lives at the lowest level that contains all its consumers. |
| Routers | One aggregator `router.py` per domain; `main.py` mounts one router per domain. Adding a feature touches the domain router, not the entrypoint. |
| Two backends | Never share a models or ORM package. Each declares its own DTOs; the schema is the only shared contract. |
| Reconcile in the same milestone | When the domain model settles or changes, move the folders then. Batch moves into a window where churn already happens; never one folder per PR across months. |

Providers of one kind (LLMs, payment gateways, storage backends) follow the adapter pattern: `modules/<provider>/` behind one `base.py` contract, one canonical output shape, and engine code that never names a provider. `07_security.md` for the AI-specific rules.

## Serving

Dev is one hot-reload process (`uvicorn --reload`, `cargo watch`). Production is not.

| Language | Production model |
|---|---|
| Python | gunicorn with uvicorn workers. `workers = (2 × cores) + 1` as a start, fewer for I/O-bound async apps; measure. Recycling `--max-requests 1000 --max-requests-jitter 100` bounds leaks and the jitter prevents a synchronised restart storm. `--timeout 60 --graceful-timeout 30 --keep-alive 5`. `--preload` in a container (you redeploy the image anyway). All in `gunicorn.conf.py` beside `pyproject.toml`, values from the environment (`WEB_CONCURRENCY`). The Dockerfile `CMD` is gunicorn; `--reload` never ships. |
| Rust | One process, Tokio threads. No workers, no recycling: a leak is fixed, not restarted around. Scale by replicas. Graceful shutdown on `SIGTERM` (`with_graceful_shutdown`). |
| Go | One process, goroutines. Scale by replicas. |
| Node | One process per container. Scale by replicas; never PM2 cluster mode inside a container the orchestrator also replicates. |

Worker count matches the container's CPU limit (`09_production.md`): nine workers on two CPUs is context-switch thrash. Graceful shutdown in every language: stop accepting, drain in-flight, close pools (lifespan hooks), exit 0. `stop_grace_period` in compose ≥ the graceful timeout.

## Migrations

Schema changes always go through migrations. Never edit a live schema by hand; never `Base.metadata.create_all()` in production.

| Way | Where | Use when |
|---|---|---|
| Alembic autogenerate | Inside the backend, next to its models | One Python backend owns the database, and the schema needs nothing autogenerate cannot express. Autogenerate, review the diff, commit. |
| Hand-written SQL | `apps/database/postgres/` | Two or more backends read the same database, or the schema uses what autogenerate handles badly: partial or expression indexes, extensions, triggers, custom types, data backfills, partitions. |
| The owner's native tool | `apps/database/postgres/` | No Python backend owns the schema: `sqlx migrate` (Rust), `golang-migrate` (Go). Same folder, same `ctl migrate` verbs. |

Both conditions must hold for autogenerate: single consumer, plain schema. If either fails, `apps/database/` owns the migrations. One owner in every case.

Hand-written with Alembic as the runner is three files per revision: a three-line `.py` shim, `.up.sql`, `.down.sql`. The shim calls `run_sql(__file__, ".up.sql")` from `alembic_helpers.py`; the SQL file is the source of truth, readable by a DBA, an operator and `sqlx` alike. `ctl migrate new "<msg>"` creates the trio; a `.down.sql` left empty says why in a comment.

Rules:

- `ctl migrate` applies them, `ctl migrate new` creates one. Never `alembic` by hand.
- Migrations are an explicit step, never on app boot. `ctl up` runs them once before the apps; with N replicas the same step is a one-shot compose service the apps `depends_on` with `service_completed_successfully` (`09_production.md`).
- The consuming language never writes DDL. A Rust query that needs a column: write the migration, run `ctl migrate`, then `cargo sqlx prepare`, then the query. The gate order is `migrate → sqlx prepare --check → build`.
- Never edit an applied migration; write a new one. Two heads (two revisions with the same `down_revision`) are squashed before merging to main; `ctl migrate status` fails on a branch.
- Autogenerate needs four things or it silently sees an empty schema and drops every table: `prepend_sys_path = .` in `alembic.ini`; `import app.models` (every model module) in `env.py` so `target_metadata` is populated; `sqlalchemy.url` set from the config loader, never `alembic.ini`; `render_as_batch=True` in both `context.configure` calls when SQLite is a target. Review and edit every generated revision; never mix generated and hand-written DDL in one file.
- Other engines follow the same verbs: Neo4j constraints in `apps/database/neo4j/init.cypher`, idempotent; Redis config in `apps/database/redis/redis.conf`.

Template: `template/apps/database/README.md`, `template/apps/database/postgres/migrations/versions/0002_indexes.py`.

## Running the engines well

| Engine | Rules that bite |
|---|---|
| Postgres | `POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --locale=C.UTF-8"` or collation drifts between machines. Numbered init scripts in `apps/database/postgres/init/` for extensions and roles, run once on an empty `pgdata`. Bind-mount a nested `pgdata/`, not `data/postgres/` itself. `pg_isready` healthcheck; apps `depends_on: service_healthy`. Backups through `ctl db backup` (`pg_dump | gzip`). |
| Redis | `--requirepass` always, dev included. `--appendonly yes --appendfsync everysec`. Streams need `--maxmemory-policy noeviction` or unread events are silently evicted. One instance, db numbers by use: 0 sessions, 1 cache, 2 rate limits, 3 streams, 4 jobs, 15 tests. Healthcheck `redis-cli -a $$REDIS_PASSWORD ping` (`$$` escapes compose). Backup: `BGSAVE` then copy `dump.rdb`, or rsync `appendonlydir/`; `ctl db backup` does both engines. Never a blob in Redis. |
| SQLite | Pragmas on every connection: `journal_mode=WAL`, `busy_timeout=5000`, `foreign_keys=ON` (off by default), `synchronous=NORMAL`. One writer at a time; a web app plus a CLI is fine, N gunicorn workers writing is the Postgres signal. The file lives under `data/sqlite/`. Backup with `.backup`, never a raw copy mid-write. |
| Neo4j | Constraints and indexes in `init.cypher`, idempotent (`IF NOT EXISTS`). Healthcheck a cypher ping. |

## The break-glass console

`manager.py` at the backend root, run by `ctl manage`: operators and platform settings without the web auth flow. It imports the app's loader and `core/security.py`, never a router. Rules: `08_ctl.md`. Template: `template/apps/example-api-python/manager.py`.
