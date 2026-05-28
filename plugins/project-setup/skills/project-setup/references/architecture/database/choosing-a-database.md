# Choosing a database / cache

The per-engine files (`postgres-conventions.md`, `redis-conventions.md`, …) cover *how* to run each. This file covers *which to pick* — the two decisions that come up most: **SQLite vs Postgres** and **in-process memory vs Redis**. Both have a low-end default that projects skip past too early.

## SQLite vs Postgres

### SQLite when

- A **single service** owns the data (no other process/service writes it)
- Small dataset, low write concurrency
- Single-node deployment
- Auth / config / metadata / feature-flag stores — small, mostly-read tables
- You want zero operational overhead (no container, no connection pool, no creds)

Operational notes for SQLite-in-production:

- Turn on **WAL mode** (`PRAGMA journal_mode=WAL`) — allows concurrent reads alongside a writer
- Set a **`busy_timeout`** (`PRAGMA busy_timeout=5000`) so a second writer (e.g. a CLI / cron) waits instead of erroring with "database is locked"
- One writer at a time is the model — design around it
- Alembic with SQLite needs `render_as_batch=True` for `ALTER`s (see `python/alembic-default.md`)

### Postgres when

- **Multiple concurrent writers**
- **Several services share** the database
- Large or growing datasets
- You need extensions / rich types — `pgvector`, JSONB, full-text search, `pg_trgm`, partitioning
- Horizontal scale, replicas, connection pooling
- Heavy analytical queries

### Rule of thumb

**Start SQLite for a single service with modest data; move to Postgres when you need concurrent writers or cross-service sharing.** Don't reach for Postgres reflexively — a 20-row admins + API-keys table does not need a Postgres container. (Real example: `neurasutra-sam-image-segmentation`'s admin + API-key store is ~20 rows — SQLite is the correct floor.) Equally, don't cling to SQLite once two services need to write the same data — that's the migration signal.

### Migration path

SQLite → Postgres is a real (if modest) migration: swap the driver, point `DATABASE_URL` at Postgres, re-run Alembic against the new DB, port any SQLite-specific SQL. Because the schema lives in Alembic and the URL comes from config (one source of truth), the blast radius is small. Plan it when the SQLite-fit conditions stop holding, not in a panic.

## In-process memory vs Redis

### In-process memory (a dict / cache inside the app) when

- **Single worker / process**
- Data is small
- Doesn't need to survive restarts or be shared across processes
- You want the **lowest possible latency** — no network hop, no serialization

Pattern: a plain dict or an `lru_cache`, rebuilt on boot from the source of truth.

(Real example: `neurasutra-sam-image-segmentation`'s API-key lookup is a dict in the single gunicorn worker, rebuilt on boot from the DB. No Redis needed — there's one process, the data is tiny, and a cold rebuild on restart is fine.)

### Redis when

- **Multiple workers / processes / services must share** state (cache, sessions, rate limits, job queues, pub/sub)
- You need **TTL** or **persistence** across restarts
- Distributed locks
- Cross-instance coordination
- Redis Streams for event-driven flows

Redis is a **network service** — it's only worth the extra moving part when you genuinely need sharing or durability beyond one process.

### Rule of thumb

**Single-process + ephemeral + small → in-memory. Shared across processes, or needs TTL / persistence / pub-sub → Redis.**

The trap is adding Redis "for caching" when the app runs as a single worker — you've added a network hop, a container, and a dependency to replace a dict. Conversely, the trap on the other side is an in-process cache when you run N gunicorn workers and each has its own stale copy — that's when you actually need Redis.

### Interaction with worker count

This decision is coupled to `references/architecture/production/app-server-and-workers.md`:

- **1 worker** → in-process cache is coherent (one copy, one source of truth)
- **N workers** → in-process caches **diverge** (each worker has its own); if cache coherence matters, you need Redis (or accept per-worker staleness for read-only data rebuilt on boot)

So "how many workers" and "in-memory vs Redis" are the same conversation. Decide them together.

## What the skill should ask

- How many services write this data? (1 → SQLite candidate; 2+ → Postgres)
- How big / how concurrent? (small + low-write → SQLite; large / concurrent → Postgres)
- For caching: how many workers/processes need the cached state? (1 → in-memory; N or cross-service → Redis)
- Does the cached/stored state need to survive restarts? (yes → Redis/Postgres; no → in-memory ok)

## Anti-patterns

- Postgres container for a 20-row single-service metadata table — SQLite is the floor
- SQLite shared by multiple writing services — that's the Postgres signal, take it
- SQLite in prod without WAL + `busy_timeout` — "database is locked" under any concurrency
- Redis for a single-worker app's cache — a dict does it with lower latency
- In-process cache across N workers when coherence matters — silent staleness per worker
- Defaulting to "Postgres + Redis" for every project regardless of scale — match the tool to the actual need

## See also

- `references/architecture/database/sqlite-conventions.md` — WAL, busy_timeout, the single-writer model
- `references/architecture/database/postgres-conventions.md`
- `references/architecture/database/redis-conventions.md`
- `references/architecture/production/app-server-and-workers.md` — why worker count drives the cache decision
