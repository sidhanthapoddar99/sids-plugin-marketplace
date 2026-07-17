# SQLite usage conventions

How to run SQLite well: connection pragmas, the single-writer model, file location, Alembic batch mode, backup. **Whether** to pick SQLite over Postgres — and when to graduate — is a choice owned by `references/2-repo/databases-provisioning.md`.

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

When these conditions stop holding, graduate to Postgres — the decision and migration path are owned by `references/2-repo/databases-provisioning.md`.

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

In Docker, mount `${DATA_DIR}` so the `.db` survives container restarts (same bind-mount discipline as Postgres — see `references/2-repo/runtime/docker-details.md`).

## Alembic with SQLite

`render_as_batch=True` is **required** — SQLite can't do most `ALTER TABLE`s in place, and batch mode transparently rebuilds the table. Set it in both the online and offline `context.configure(...)` calls. See `references/3-app/backend/alembic-recipe.md`.

## Backup

A SQLite backup is a file copy — but do it through the API to avoid copying mid-write:

```bash
sqlite3 data/sqlite/app.db ".backup 'backups/app-$(date +%F).db'"
```

Or just stop the writer and `cp` the file (+ the `-wal` and `-shm` sidecar files if present).

## When to graduate to Postgres

The graduation decision (second service writes the data, write concurrency climbs, extensions/types needed, dataset strains the single-file model) plus the migration path is owned by `references/2-repo/databases-provisioning.md`. The migration is modest because the schema lives in Alembic and the URL lives in config.

## Anti-patterns

- No WAL / no `busy_timeout` in prod — "database is locked" under any concurrency
- Committing the `.db` file — it's state, gitignore it (`.gitkeep` the dir)
- FK constraints assumed on but never enabled (`PRAGMA foreign_keys=ON` missing)
- Heavy multi-writer load on SQLite — wrong tool; graduate to Postgres
- Alembic migrations without `render_as_batch=True` — `ALTER` fails on SQLite

## See also

- `references/2-repo/databases-provisioning.md` — SQLite vs Postgres (the choice) + graduation/migration path
- `references/3-app/backend/alembic-recipe.md` — batch-mode Alembic mechanics
- `references/3-app/database-usage/postgres.md` — the graduation target
