# Databases — engine choice + provisioning

Owns the repo-level database decisions: **which engine** (SQLite vs Postgres, in-process memory vs Redis, plus the cross-engine selection table for everything else) and **where its files live** (`infra/` config vs `data/` state). Both have a low-end default that projects skip past too early. Per-engine *usage* conventions (how to run and query each) live in `references/3-app/database-usage/`.

## SQLite vs Postgres

### SQLite when

- A **single service** owns the data (no other process/service writes it)
- Small dataset, low write concurrency
- Single-node deployment
- Auth / config / metadata / feature-flag stores — small, mostly-read tables
- You want zero operational overhead (no container, no connection pool, no creds)

Running SQLite well in production (WAL, `busy_timeout`, the single-writer model, Alembic batch mode) is usage, owned by `references/3-app/database-usage/sqlite.md`.

### Postgres when

- **Multiple concurrent writers**
- **Several services share** the database
- Large or growing datasets
- You need extensions / rich types — `pgvector`, JSONB, full-text search, `pg_trgm`, partitioning
- Horizontal scale, replicas, connection pooling
- Heavy analytical queries

### Rule of thumb

**Start SQLite for a single service with modest data; move to Postgres when you need concurrent writers or cross-service sharing.** Don't reach for Postgres reflexively — a 20-row admins + API-keys table does not need a Postgres container; SQLite is the correct floor. Equally, don't cling to SQLite once two services need to write the same data — that's the migration signal.

### Migration path

SQLite → Postgres is a real (if modest) migration: swap the driver, point `DATABASE_URL` at Postgres, re-run Alembic against the new DB, port any SQLite-specific SQL. Because the schema lives in Alembic and the URL comes from config (one source of truth), the blast radius is small. Plan it when the SQLite-fit conditions stop holding, not in a panic.

## In-process memory vs Redis

### In-process memory (a dict / cache inside the app) when

- **Single worker / process**
- Data is small
- Doesn't need to survive restarts or be shared across processes
- You want the **lowest possible latency** — no network hop, no serialization

Pattern: a plain dict or an `lru_cache`, rebuilt on boot from the source of truth — e.g. an API-key lookup held in the single gunicorn worker, rebuilt on boot from the DB. No Redis needed when there's one process, the data is tiny, and a cold rebuild on restart is fine.

### Redis when

- **Multiple workers / processes / services must share** state (cache, sessions, rate limits, job queues, pub/sub)
- You need **TTL** or **persistence** across restarts
- Distributed locks
- Cross-instance coordination
- Redis Streams for event-driven flows

Redis is a **network service** — it's only worth the extra moving part when you genuinely need sharing or durability beyond one process.

### Rule of thumb

**Single-process + ephemeral + small → in-memory. Shared across processes, or needs TTL / persistence / pub-sub → Redis.**

The trap is adding Redis "for caching" when the app runs as a single worker — you've added a network hop, a container, and a dependency to replace a dict. The trap on the other side is an in-process cache when you run N workers and each has its own stale copy — that's when you actually need Redis.

### Coupled to worker count

This decision is inseparable from the per-language worker model (owned by `references/3-app/backend/serving.md`):

- **1 worker** → in-process cache is coherent (one copy, one source of truth)
- **N workers** → in-process caches **diverge** (each worker has its own); if cache coherence matters, you need Redis (or accept per-worker staleness for read-only data rebuilt on boot)

"How many workers" and "in-memory vs Redis" are the same conversation — decide them together.

## When to pick which — beyond the default pair

The two decisions above cover most projects. When a claimed need points past Postgres + Redis, check the table before adding a container:

| Need | Pick |
|---|---|
| Relational, ACID, the answer for 80% of cases | Postgres |
| Cache, sessions, pub/sub, streams | Redis |
| Document model where schemas are truly variable | MongoDB |
| Graph queries dominate | Neo4j |
| Embedded graph DB, no separate container | Kuzu |
| Blob storage, S3-compatible, self-hosted | SeaweedFS |
| Fuzzy search with typo tolerance | Meilisearch |
| Vector embeddings | pgvector (Postgres extension) — usually before pulling in a separate vector DB |
| Time-series at scale | TimescaleDB (Postgres extension) before reaching for InfluxDB / Prometheus |

**Default to Postgres + Redis. Add others only when there's evidence a Postgres extension can't do the job.** The extension escape hatch is real: vector, time-series, and fuzzy search all live inside Postgres (see `references/3-app/database-usage/postgres.md` for the extension table). Usage conventions for the non-default engines are in `references/3-app/database-usage/other-engines.md`.

## `infra/` (config) vs `data/` (state)

Two top-level folders, two different purposes. Easy to conflate; keep distinct.

### `infra/` — config baked into containers

Read-only at runtime. Mounted into containers as ConfigMap-equivalents. Committed.

```
infra/
├── nginx/
│   └── nginx.conf
├── postgres/
│   └── init/
│       └── 01_extensions.sql        # mounted to /docker-entrypoint-initdb.d
├── redis/
│   └── redis.conf
├── traefik/
│   └── dynamic.yaml                  # reference — only used if Traefik is in scope
└── seaweed/
    └── filer.toml
```

### `data/` — state mounted from host

Read-write at runtime. Bind-mount targets. Gitignored (except `.gitkeep`).

```
data/
├── postgres/
│   └── pgdata/                       # bind-mounted; first-run-empty
├── redis/
│   └── data/                         # AOF file
├── seaweed/
│   ├── master/
│   ├── volume/
│   └── filer/
└── meili/
    └── data.ms/
```

### Why split

| `infra/` | `data/` |
|---|---|
| Committed | Gitignored |
| Read-only inside container | Read-write inside container |
| Code-reviewed | Operational |
| Migration target during ops | Backup target during ops |

Putting `nginx.conf` and postgres data in the same `postgres/` folder makes review/backup workflows confused. Keep concerns physically separate.

### compose references both

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    volumes:
      # data (mutable)
      - ${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data
      # infra (read-only config)
      - ../infra/postgres/init:/docker-entrypoint-initdb.d:ro

  nginx:
    image: nginx:1.27-alpine
    volumes:
      - ../infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
```

The `:ro` (read-only) flag on infra mounts is the discipline marker.

### `.gitignore`

`data/` is gitignored except `.gitkeep` markers; `infra/` is fully committed. The exact negation pattern (and the whole `.gitignore` doctrine) is owned by `references/2-repo/root-and-hygiene.md` § gitignore.

### `${DATA_DIR}` override

The compose files use `${DATA_DIR:-../data}` so the data location is env-configurable per environment — override mechanics owned by `references/2-repo/runtime/docker-details.md`. `infra/` is **always** at `../infra/` relative to `docker/` — not env-configurable. It's source.

### When a service has both config and data

Postgres is the canonical example:

- Config: `infra/postgres/init/01_extensions.sql` (and `postgresql.conf` if customised)
- Data: `data/postgres/pgdata/` (bind-mount, gitignored)

Mount both. Different `:ro` / `:rw` semantics.

## What the skill should ask

- How many services write this data? (1 → SQLite candidate; 2+ → Postgres)
- How big / how concurrent? (small + low-write → SQLite; large / concurrent → Postgres)
- For caching: how many workers/processes need the cached state? (1 → in-memory; N or cross-service → Redis)
- Does the cached/stored state need to survive restarts? (yes → Redis/Postgres; no → in-memory ok)

## Anti-patterns

- Postgres container for a 20-row single-service metadata table — SQLite is the floor
- SQLite shared by multiple writing services — that's the Postgres signal, take it
- Redis for a single-worker app's cache — a dict does it with lower latency
- In-process cache across N workers when coherence matters — silent staleness per worker
- Defaulting to "Postgres + Redis" for every project regardless of scale — match the tool to the actual need
- Putting `data/postgres/init/` and `data/postgres/pgdata/` under the same parent — split into `infra/postgres/` and `data/postgres/`
- Committing `data/postgres/pgdata/*` accidentally — `.gitignore` strictly
- Mutating `infra/` files at runtime — they're meant to be code-reviewed and re-deployed
- `infra/` containing secrets — secrets are env vars, not config files
- Different conventions per service in the same repo — be uniform

## See also

- `references/3-app/database-usage/sqlite.md` — WAL, busy_timeout, the single-writer model
- `references/3-app/database-usage/postgres.md` — Postgres usage conventions
- `references/3-app/database-usage/redis.md` — Redis usage conventions
- `references/3-app/database-usage/other-engines.md` — Mongo / Neo4j / SeaweedFS usage
- `references/3-app/backend/serving.md` — why worker count drives the cache decision
- `references/3-app/backend/migrations.md` — Alembic vs raw-SQL vs no-tool (schema-change decision)
- `references/2-repo/root-and-hygiene.md` — `.gitignore` doctrine (the `data/**` negation pattern)
