# Alembic — the default migration tool

For Python backends. Mature, well-supported, integrates with SQLAlchemy. Default for new projects unless there's a compelling reason otherwise.

## Layout

```
apps/backend/
├── alembic/
│   ├── env.py                       # Alembic config, reads database URL from config.yaml or env
│   ├── script.py.mako               # template for new revisions
│   └── versions/                    # the actual migrations
│       ├── 001_initial.py
│       ├── 002_add_users.py
│       └── 003_add_index.py
└── alembic.ini
```

## Initial setup — the concrete recipe

```bash
# from the backend dir (flat layout — see python/pyproject-uv-sync-for-apps.md)
cd apps/backend            # or ./api for a single service
uv add alembic sqlalchemy asyncpg
alembic init alembic       # creates alembic/ + alembic.ini

# 1) alembic.ini:
#      script_location = alembic
#      prepend_sys_path = .          # so `app` is importable (flat layout; use `src` only for a package)
#      # leave sqlalchemy.url EMPTY — env.py sets it from config (one source of truth)

# 2) alembic/env.py:
#      from app.db import Base                 # your declarative Base
#      import app.models                       # noqa — importing registers tables on Base.metadata
#      from app.config import settings
#      config.set_main_option("sqlalchemy.url", settings.db_url)   # one source of truth
#      target_metadata = Base.metadata
#      # in BOTH the online AND offline configure() calls:
#      #   render_as_batch=True               # REQUIRED for SQLite ALTERs (no-op on Postgres)

# 3) first migration:
alembic revision -m "initial"   # hand-write the DDL, or add --autogenerate
alembic upgrade head
```

Why each line:

- **`prepend_sys_path = .`** — makes `app` importable when alembic runs from the backend root. The **flat `app/` layout makes this trivial** — no `PYTHONPATH` gymnastics, no `src` on the path. (A distributable package would use `prepend_sys_path = src`.) This is a concrete payoff of the run-service layout.
- **`import app.models`** — importing the module is what registers every table on `Base.metadata`. Without it, `--autogenerate` sees an empty schema and "drops" all your tables.
- **`config.set_main_option("sqlalchemy.url", settings.db_url)`** — the URL comes from your config (which reads root `.env` via `${VAR}`), so there's exactly one source of truth and no secret in `alembic.ini`.
- **`render_as_batch=True`** — SQLite can't do most `ALTER TABLE`s in place; batch mode rebuilds the table transparently. Harmless on Postgres, mandatory if SQLite is in the mix. Set it in both the online and offline `context.configure(...)` blocks.

## `alembic.ini` essentials

```ini
[alembic]
script_location = alembic
file_template = %%(year)d%%(month).2d%%(day).2d_%%(rev)s_%%(slug)s
timezone = UTC
# leave sqlalchemy.url empty — env.py reads it from config.yaml

[loggers]
keys = root,sqlalchemy,alembic

# ... standard logger config
```

## Daily flow

```bash
# create a revision
ctl migrate new "add users table"
# → alembic/versions/20260520_abc123_add_users_table.py

# write the migration
# ... edit the file ...

# apply
ctl migrate up

# rollback last
ctl migrate down

# check current
ctl migrate status
```

## Migrations in Docker — the container migrates itself

For the containerized path, **don't leave migrations as a manual human step.** The backend container's **entrypoint runs `alembic upgrade head` on boot**, before launching the server, so the schema on the mounted volume is brought up to date automatically — first run *and* every subsequent boot (idempotent: if already at head, it's a no-op).

```sh
# apps/backend/docker-entrypoint.sh
#!/bin/sh
set -e
alembic upgrade head            # bring the mounted DB to head; no-op if already current
exec "$@"                       # then run the CMD (gunicorn / uvicorn)
```

```dockerfile
# in the backend Dockerfile
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "app.main:app", "-c", "gunicorn.conf.py"]
```

This is the **simple default** — correct for single-replica deployments, dev, and SQLite/single-Postgres setups. First `docker compose up` and the schema just exists; no separate migrate command.

**The multi-replica caveat:** if you run **N replicas of the backend**, having every replica race to `alembic upgrade head` on boot is a problem (concurrent migrations, lock contention). At that scale, switch to a **separate one-shot migrate service that runs before the app replicas start** — see `references/architecture/production/production-readiness.md` § "Migrations on deploy". Rule of thumb: **entrypoint-migrates for single-replica; one-shot migrate service for multi-replica.** Same `alembic upgrade head`, different orchestration.

## Autogenerate vs hand-write

```bash
uv run alembic revision --autogenerate -m "add users"
```

Autogenerate compares SQLAlchemy models to the current schema and writes the diff.

**Use autogenerate when**:
- Simple column additions/removals
- New tables with no special constraints
- Index changes

**Hand-write when**:
- Partitioning, hash partitions, complex constraints
- Data migrations (UPDATE statements)
- Extension installations (`CREATE EXTENSION pgvector`)
- Multi-tenant schema setup
- Anything Alembic can't introspect (custom types, raw SQL features)

Autogenerated migrations should be **reviewed and edited** — Alembic misses things (e.g. it doesn't always detect column renames; it sees a drop + create).

## When to use raw-SQL + shim pattern

If Rust or another non-Python service consumes the schema, the raw-SQL pattern (see `alembic-with-raw-sql.md`) makes the SQL the source of truth. Default to plain Alembic for Python-only projects.

## env.py — the loader

```python
# alembic/env.py
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import yaml, os, re

from my_app.models import Base  # your SQLAlchemy declarative base

config = context.config
fileConfig(config.config_file_name)

# Load database URL from config.yaml with ${VAR} substitution
def _load_db_url() -> str:
    with open("config.yaml") as f:
        text = f.read()
    text = re.sub(r"\$\{([A-Z0-9_]+)\}",
                  lambda m: os.environ.get(m.group(1), ""), text)
    cfg = yaml.safe_load(text)
    return cfg["database"]["url"]

config.set_main_option("sqlalchemy.url", _load_db_url())
target_metadata = Base.metadata

# ... rest is standard
```

## Anti-patterns

- Editing applied migrations — write a new one
- Committing autogenerated migrations without reviewing — Alembic doesn't read your mind
- Branching migrations (multiple `down_revision = `) — squash before merging to main
- Storing migrations outside `alembic/versions/` — Alembic won't find them
- Mixing autogen and hand-write in the same revision file — split for clarity
