# Backend — how a backend is built

The language is chosen in `04_stack.md`; the env contract is `02_env.md`; routing is `03_routing.md`. This page is the inside: the layout by size, domain slices, serving, migrations, the engines. Template: `template/apps/example-api-python/`, `template/apps/example-engine-rust/`, `template/apps/database/`.

## Every backend has

| Piece | Rule |
|---|---|
| One config loader | `config.py` / `config.rs` / `config.go`. Nothing else reads the environment or a file. `02_env.md`. |
| `/health` and `/ready` | Two endpoints, two actions: `09_production.md` § Health. |
| Its own prefix | `<PIECE>_HOST/_PORT/_PREFIX` in `.env`; it binds `_PORT` and mounts `_PREFIX`. |
| Rate limiting at the router | Keyed on the user or API key, never the raw IP for authenticated routes. `07_security.md`. |
| `X-Forwarded-*` trusted from the edge only | Never CORS middleware for our own frontend. |
| Its own image | Non-root user, multi-stage, pinned base, no dev deps in the runtime stage, no `COPY .env*`. |
| Its own suite | Unit tests beside the file, integration in `tests/` beside `app/`. `10c_dynamic-tests.md`. Layer rules are lint config: `10b_static-checks.md`. |

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
| The layers | One job each: `router` parses, authorises, calls, serialises; `service` holds the rule and is the domain's only public surface; `repository` runs the query, given a connection, and the caller owns the transaction; `models` are the request and response types that `@scope/types` is generated from. A layer with two jobs cannot be tested alone. |
| Inside a slice | `router → service → repository`. Never backwards, because a repository that calls a service hides a second rule behind the query. |
| Across slices | `service → service` only. A domain never touches another domain's `repository` or imports its `models` to reuse a shape: duplicate the DTO. `11_conventions.md` § Scope says why. |
| Domain names | Nouns of ownership, never activities and never UI navigation labels. `catalog/`, `orders/`, `access/`; not `build/`, `sync/`, `ingest/`. Test: an activity says what the code does this quarter; an ownership noun says what it is responsible for permanently. A pipeline that builds a catalog lives in `catalog/`. |
| Domains ≠ navigation | The UI groups by workflow; the backend by ownership. Two nav groups may map to one domain. The mapping is a recorded decision in `AGENTS.md`, never an implicit mirror. |
| Ambiguous placement | A `dashboard` that aggregates everything, an `images` feature two domains use: put it somewhere defensible and record the one-line why. |
| Domain-shared code | At the domain root (`app/<domain>/`), not in `core/`. `core/` is for code every domain uses. Code lives at the lowest level that contains all its consumers. |
| Routers | One aggregator `router.py` per domain; `main.py` mounts one router per domain. Adding a feature touches the domain router, not the entrypoint. |
| Two backends | Never share a models or ORM package. Each declares its own DTOs; the schema is the only shared contract. |
| Reconcile in the same milestone | When the domain model settles or changes, move the folders then. Batch moves into a window where churn already happens; never one folder per PR across months. |

Providers of one kind (LLMs, payment gateways, storage backends) follow the adapter pattern: `modules/<provider>/` behind one `base.py` contract, one canonical output shape, and engine code that never names a provider, because a provider swap is then one folder and no engine test changes. This paragraph is the home of the rule; `07_security.md` adds the key-handling rules for AI providers and `11_conventions.md` points here.

## Serving

Dev uses one reload workflow per service. Python can use `uvicorn --reload`; the Rust workflow is defined in `08_ctl.md` under Controllers and Rust development. Production does not run development watchers.

| Language | Production model |
|---|---|
| Python | gunicorn with uvicorn workers. `workers = (2 × cores) + 1` as a start, fewer for I/O-bound async apps; measure. Recycling `--max-requests 1000 --max-requests-jitter 100` bounds leaks and the jitter prevents a synchronised restart storm. `--timeout 60 --graceful-timeout 30 --keep-alive 5`. `--preload` in a container (you redeploy the image anyway). All in `gunicorn.conf.py` beside `pyproject.toml`, values from the environment (`WEB_CONCURRENCY`). The template does not carry this file; write it per project. The Dockerfile `CMD` is gunicorn; `--reload` never ships. |
| Rust | One process, Tokio threads. No workers, no recycling: a leak is fixed, not restarted around. Scale by replicas. Graceful shutdown on `SIGTERM` (`with_graceful_shutdown`). |
| Go | One process, goroutines. Scale by replicas. |
| Node | One process per container. Scale by replicas; never PM2 cluster mode inside a container the orchestrator also replicates. |

Worker count matches the container's CPU limit (`09_production.md`): nine workers on two CPUs is context-switch thrash. Graceful shutdown in every language: stop accepting, drain in-flight, close pools (lifespan hooks), exit 0. `stop_grace_period` in compose ≥ the graceful timeout.

## Migrations

Use Flyway for relational database migrations in every project, regardless of the
backend language. Keep SQL under `apps/database/postgres/migrations/`. Pin Flyway in the migration Dockerfile so development and
production use the same runner. The host needs Docker, not a Flyway installation. Flyway owns the history table and checksums;
do not add another ledger, ORM migration runner or schema fingerprint protocol.

Use `ctl db migrate new "description"` to create a versioned SQL file. Write the
schema or data changes in that file. Use `ctl db migrate` to apply pending files
through the Compose migration container. Use `status` to inspect migration state and `check` to validate
applied files against the current checkout. These commands do not infer SQL from
application source changes. Applied migrations are immutable; create a new forward
migration to correct one. Automatic downgrade and destructive clean are disabled.

Put required extensions and schema initialization in the first migration so a
fresh database has one initialization path. An application never migrates during
its own boot. Production Compose runs the Flyway one-shot after PostgreSQL becomes
healthy; applications wait for its successful completion. Backup, restore and
engine lifecycle remain separate CTL commands using the engine's native tools.

A query that needs a new column requires a migration before it can run. Apply that
migration before preparing or compiling schema-checked queries. Test fresh database
creation, repeated application, pending changes, checksum mismatch and failure
rollback against disposable storage. Version records stay inside the database;
SQL migration files stay in Git. Do not stamp an existing nonempty database as
current without an explicit adoption plan. Reset only when the user authorizes it.

Flyway does not manage every storage service. Neo4j constraints use the declared
`neo4j-init` service; Redis uses its config file. Object-store bucket initialization
is an application storage step, not a SQL migration. Keep those ownership boundaries
explicit instead of routing unrelated storage through Flyway.

Template: `template/apps/database/README.md`,
`template/apps/database/postgres/migrations/V1__extensions.sql` and
`template/scripts/db/migrate.sh`.

## Running the engines well

| Engine | Rules that bite |
|---|---|
| Postgres | `POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --locale=C.UTF-8"` or collation drifts between machines. Extensions and roles belong in Flyway migrations, following Migrations above. Bind-mount a nested `pgdata/`, not `data/postgres/` itself. `pg_isready` healthcheck; apps `depends_on: service_healthy`. Backups through `ctl db backup` (`pg_dump | gzip`). |
| Redis | `--requirepass` always, dev included. `--appendonly yes --appendfsync everysec`. Streams need `--maxmemory-policy noeviction` or unread events are silently evicted. One instance, db numbers by use: 0 sessions, 1 cache, 2 rate limits, 3 streams, 4 jobs, 15 tests. Healthcheck `redis-cli -a $$REDIS_PASSWORD ping` (`$$` escapes compose). Backup: `BGSAVE` then copy `dump.rdb`, or rsync `appendonlydir/`; `ctl db backup` does both engines. Never a blob in Redis. |
| SQLite | Pragmas on every connection: `journal_mode=WAL`, `busy_timeout=5000`, `foreign_keys=ON` (off by default), `synchronous=NORMAL`. One writer at a time; a web app plus a CLI is fine, N gunicorn workers writing is the Postgres signal. The file lives under `data/sqlite/`. Backup with `.backup`, never a raw copy mid-write. |
| Neo4j | Constraints and indexes in `init.cypher`, idempotent (`IF NOT EXISTS`). Healthcheck a cypher ping. |

## The break-glass console

`manager.py` at the backend root, run by `ctl manage`: operators and platform settings without the web auth flow. It imports the app's loader and `core/security.py`, never a router. Rules: `08_ctl.md`. Template: `template/apps/example-api-python/manager.py`.

## Rust and WASM — opt-in

Add this workflow only when a project actually compiles Rust to WebAssembly. The base template installs no WASM target, bindings generator or watcher. Record the target, selected toolchain, required packaging tools and versions, output directory and compatibility contract in that project's `AGENTS.md`, because a browser module and a WASI module need different targets and runtimes.

### Setup and builds

Run tool checks from the crate's working directory after activating the project's tools, so a nested `rust-toolchain.toml` or mise configuration is respected. For a rustup-managed project, identify the selected toolchain with `rustup show active-toolchain`. Verify its target using `rustup target list --installed --toolchain <selected-toolchain>`; install a missing target with `rustup target add --toolchain <selected-toolchain> <target>`. Checking the default toolchain proves nothing about a different toolchain used by the build. Check each packaging tool with its version command before compiling. [Rustup cross-compilation](https://rust-lang.github.io/rustup/cross-compilation.html).

Give the project's CTL worker distinct development and production paths. Development may use `cargo build --profile dev --target <target>`; production explicitly uses `cargo build --release --target <target>` or an approved release-derived profile. Select the toolchain identically in setup and build. Do not let an inherited development-mode flag select production output. Validate the chosen profile and output location before packaging, because successful compilation of a debug artifact is not a release build. Cargo's normal build default is the development profile. [Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html).

### Watching and activation

- Watch only the crate's source, manifests, lockfile and declared build inputs. Exclude generated bindings, output directories, `target`, dependencies and virtual environments so a build cannot trigger itself.
- Debounce bursts of edits and serialize builds. If an edit arrives during a build, schedule one further build after it finishes; never let two builds write the same candidate output.
- Build into a candidate directory. Check the complete artifact set before replacing the last good output. A failed build reports failure while retaining the last good artifacts; it does not announce the new source as active.
- Activate only compatible artifacts. Check the project's declared ABI or protocol version against its consumers. For an incompatible change, coordinate a restart or a project-specific transition; file replacement alone does not make existing browser sessions or server instances compatible.
- Stop the watcher and its owned build process on interruption. Production consumes a completed release artifact and never starts the development watcher.

If the project adds an executable watcher, test burst coalescing, edits during a build, build failure, interruption, retention of the last good artifact and rejection of a development profile on the production path. These tests belong to that opt-in workflow; they do not impose a WASM runtime or document-draining API on other projects.
