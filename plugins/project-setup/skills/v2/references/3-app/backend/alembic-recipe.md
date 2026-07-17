# Alembic recipe — mechanics

Setup and daily mechanics for the Alembic migration style. Zero decisions here — **which** style to use (Alembic vs raw-SQL vs native tool vs none) and **which** run model (entrypoint vs one-shot vs neutral owner) are owned by `references/3-app/backend/migrations.md`. This file is the concrete "how".

## Layout

```
apps/backend/
├── alembic/
│   ├── env.py                       # Alembic config; reads the DB URL from config.yaml / env
│   ├── script.py.mako               # template for new revisions
│   └── versions/                    # the actual migrations
│       ├── 001_initial.py
│       ├── 002_add_users.py
│       └── 003_add_index.py
└── alembic.ini
```

## Initial setup

```bash
# from the backend dir (flat layout — see references/3-app/backend/app-skeleton.md)
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

- **`prepend_sys_path = .`** — makes `app` importable when alembic runs from the backend root. The flat `app/` layout makes this trivial — no `PYTHONPATH` gymnastics, no `src` on the path. (A distributable package would use `prepend_sys_path = src`.)
- **`import app.models`** — importing the module is what registers every table on `Base.metadata`. Without it, `--autogenerate` sees an empty schema and "drops" all your tables.
- **`config.set_main_option("sqlalchemy.url", settings.db_url)`** — the URL comes from config (which reads root `.env` via `${VAR}` — see `references/2-repo/env-and-config/per-service-config.md`), so there's exactly one source of truth and no secret in `alembic.ini`.
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

## `env.py` — the loader

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

## Daily flow

```bash
# create a revision
ctl migrate new "add users table"
# → alembic/versions/20260520_abc123_add_users_table.py

# write the migration
# ... edit the file ...

ctl migrate up       # apply
ctl migrate down     # rollback last
ctl migrate status   # current revision
```

Autogenerate (compares SQLAlchemy models to the live schema and writes the diff):

```bash
uv run alembic revision --autogenerate -m "add users"
```

Always review and edit the output before committing. When to reach for autogenerate vs hand-write is owned by `references/3-app/backend/migrations.md`.

## Docker entrypoint — the container migrates itself

The mechanics of the **entrypoint-migrates** run model (the single-replica default; run-model choice owned by `references/3-app/backend/migrations.md`). The backend container's entrypoint runs `alembic upgrade head` on boot, before launching the server — first run and every subsequent boot (idempotent: a no-op if already at head).

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

For the multi-replica (one-shot) and two-backend (neutral `apps/db`) variants, see the run-model table in `references/3-app/backend/migrations.md`.

## Recipe hygiene

- Editing an applied migration → write a new one instead.
- Committing an autogenerated revision without reviewing it — Alembic doesn't read your mind (it can miss renames).
- Branching migrations (multiple `down_revision =`) — squash before merging to main.
- Storing migrations outside `alembic/versions/` — Alembic won't find them.
- Mixing autogen and hand-write in the same revision file — split for clarity.

## See also

- `references/3-app/backend/migrations.md` — the style + run-model decisions this recipe implements
- `references/3-app/backend/raw-sql-recipe.md` — the raw-SQL variant's mechanics
- `references/3-app/backend/app-skeleton.md` — the flat `app/` layout and `pyproject` + `uv` flow
- `references/2-repo/env-and-config/per-service-config.md` — the `config.yaml` + `${VAR}` the URL loader reads
- `references/3-app/database-usage/sqlite.md` — why `render_as_batch=True` is required for SQLite
