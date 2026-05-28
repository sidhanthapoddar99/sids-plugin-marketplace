# SQLite conventions

The right floor for a single service with modest data (auth, config, metadata, feature flags). For *whether* to pick it over Postgres, see `choosing-a-database.md`. This file is *how* to run it well.

## Pragmas — set these on every connection

```python
# app/db.py
from sqlalchemy import create_engine, event

engine = create_engine(settings.db_url, connect_args={"check_same_thread": False})

@event.listens_for(engine, "connect")
def _set_sqlite_pragmas(dbapi_conn, _):
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL")      # concurrent reads alongside a writer
    cur.execute("PRAGMA busy_timeout=5000")     # wait up to 5s instead of "database is locked"
    cur.execute("PRAGMA foreign_keys=ON")       # SQLite has FKs OFF by default
    cur.execute("PRAGMA synchronous=NORMAL")    # safe with WAL, much faster than FULL
    cur.close()
```

| Pragma | Why |
|---|---|
| `journal_mode=WAL` | Readers don't block the writer and vice-versa — essential for any concurrency (e.g. web app + a CLI) |
| `busy_timeout=5000` | A second writer waits for the lock instead of erroring immediately |
| `foreign_keys=ON` | SQLite disables FK enforcement by default — turn it on |
| `synchronous=NORMAL` | With WAL this is durable enough and far faster than the default `FULL` |

## The single-writer model

SQLite allows **one writer at a time** (readers are concurrent under WAL). Design around it:

- A web app (one writer path) + a CLI / cron (occasional second writer) is fine with `busy_timeout`
- Many concurrent writers is **not** SQLite's job — that's the Postgres signal
- Don't run N gunicorn workers all writing heavily to one SQLite file and expect Postgres-like throughput

## File location

The `.db` file is **state** — it lives under the bind-mounted `data/` dir, gitignored:

```
data/
└── sqlite/
    └── app.db          # gitignored; data/sqlite/.gitkeep committed
```

```yaml
# config.yaml
database:
  url: sqlite:///${DATA_DIR:-./data}/sqlite/app.db
```

In Docker, mount `${DATA_DIR}` so the `.db` survives container restarts (same bind-mount discipline as Postgres — see `bind-mounts-not-volumes.md`).

## Alembic with SQLite

`render_as_batch=True` is **required** — SQLite can't do most `ALTER TABLE`s in place, and batch mode transparently rebuilds the table. Set it in both the online and offline `context.configure(...)` calls. See `python/alembic-default.md`.

## Backup

A SQLite backup is a file copy — but do it through the API to avoid copying mid-write:

```bash
sqlite3 data/sqlite/app.db ".backup 'backups/app-$(date +%F).db'"
```

Or just stop the writer and `cp` the file (+ the `-wal` and `-shm` sidecar files if present).

## When to graduate to Postgres

- A second service needs to write the data
- Write concurrency climbs past "occasional"
- You need extensions / types SQLite lacks
- Dataset grows large enough that SQLite's single-file model strains

The migration is modest because the schema is in Alembic and the URL is in config — see `choosing-a-database.md` § "Migration path".

## Anti-patterns

- No WAL / no `busy_timeout` in prod — "database is locked" under any concurrency
- Committing the `.db` file — it's state, gitignore it (`.gitkeep` the dir)
- FK constraints assumed on but never enabled (`PRAGMA foreign_keys=ON` missing)
- Heavy multi-writer load on SQLite — wrong tool; move to Postgres
- Alembic migrations without `render_as_batch=True` — `ALTER` fails on SQLite
