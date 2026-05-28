# Alembic with raw SQL + 3-line shim — for multi-language schema consumers

When Rust, Go, or another non-Python service queries the same Postgres schema, the **DDL becomes a contract**, not a Python implementation detail. Atheneum's pattern: schema authored in raw `.sql` files, Alembic runs them via a 3-line Python shim per migration.

## Why

- **Rust's sqlx** does offline compile-time query checking against the migrated schema. The schema must be readable by Rust tooling — Python ORM models aren't a contract for non-Python consumers.
- **DBAs and operators** can read `.sql` files. `Base.metadata.create_all` results aren't reviewable.
- **Hand-tuned DDL** (partitioning, complex constraints, extensions) is verbose in SQLAlchemy and natural in SQL.
- **Single source of truth** — the SQL file. Python is just the runner.

## The three-file-per-revision pattern

Each migration is **three files** that travel together:

```
apps/backend-python/alembic/versions/
├── 20260520_abc123_add_users.py             # 3-line shim
├── 20260520_abc123_add_users.up.sql         # the actual DDL — source of truth
└── 20260520_abc123_add_users.down.sql       # rollback (may be empty for forward-only)
```

## The shim

```python
# 20260520_abc123_add_users.py
"""add users — see .up.sql for the actual DDL.

Revision ID: abc123
Revises: prev456
Create Date: 2026-05-20 …
"""
from alembic_helpers import run_sql

revision = "abc123"
down_revision = "prev456"
branch_labels = None
depends_on = None

def upgrade() -> None:
    run_sql(__file__, ".up.sql")

def downgrade() -> None:
    run_sql(__file__, ".down.sql")
```

`alembic_helpers.run_sql` reads the sibling `.sql` file and executes it via `op.execute`:

```python
# alembic_helpers.py
from pathlib import Path
from alembic import op

def run_sql(py_file: str, suffix: str) -> None:
    sql_path = Path(py_file).with_suffix(suffix)
    if not sql_path.exists():
        return                       # empty .down.sql ok for forward-only
    sql = sql_path.read_text()
    if not sql.strip():
        return
    op.execute(sql)
```

## The SQL file

```sql
-- 20260520_abc123_add_users.up.sql

CREATE TABLE users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       uuid NOT NULL,
  email        text UNIQUE NOT NULL,
  display_name text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
) PARTITION BY HASH (org_id);

-- 32 partitions
DO $$
BEGIN
  FOR i IN 0..31 LOOP
    EXECUTE format(
      'CREATE TABLE users_p%s PARTITION OF users FOR VALUES WITH (MODULUS 32, REMAINDER %s)',
      i, i
    );
  END LOOP;
END$$;

CREATE INDEX ON users (org_id, email);
```

DBAs / operators / sqlx all read this file. There's no ORM intermediary.

## `ctl migrate new` automates the file pair

```bash
ctl migrate new "add ideas table"
```

In the dispatcher:

```bash
cmd_migrate_new() {
  local msg="$1"
  ( cd apps/backend-python && uv run alembic revision -m "$msg" ) | tee /tmp/mig.out

  local revfile
  revfile=$(grep -oE 'apps/backend-python/alembic/versions/[^ ]+\.py' /tmp/mig.out | head -n1 || true)
  if [[ -n "$revfile" ]]; then
    local base="${revfile%.py}"
    : > "${base}.up.sql"
    : > "${base}.down.sql"
    c_ok "Created:"
    printf '    %s\n' "$revfile" "${base}.up.sql" "${base}.down.sql"
  fi
}
```

Generated `.py` shim + empty `.up.sql` and `.down.sql` ready to fill.

## The cross-language drift check

After every migration, regenerate Rust's offline metadata:

```bash
ctl sqlx-prepare
```

Which runs:

```bash
( cd apps/backend-rust && DATABASE_URL="${DATABASE_URL}" cargo sqlx prepare --workspace )
```

This writes `.sqlx/` files Rust uses for offline query verification. `ctl` runs:

```
migrate up → sqlx prepare --check → cargo build
```

…in that order on every invocation. Drift fails locally before code lands.

**The rule**: Rust never writes DDL. If a Rust query needs a column, write the Alembic migration first, then regenerate `.sqlx/`, then add the query.

## When to use this pattern

- Multi-language schema consumers (Rust + Python, Go + Python)
- Complex DDL (partitioning, custom types, extensions)
- DBAs in the loop
- Strong reviewability of schema changes

When to NOT use:

- Python-only — plain Alembic + autogen is simpler
- Schemas that change rarely — overhead not worth it
- Teams that prefer ORM-first

## Anti-patterns

- Letting Rust autogenerate the schema from sqlx queries — Rust loses; schema becomes implicit
- Writing the `.up.sql` and forgetting the shim — Alembic won't apply it
- `op.execute` blocks inside the Python shim — defeats the source-of-truth split
- `.down.sql` always empty silently — at least comment why it's forward-only

## Real-world reference

- atheneum — the canonical example. See `apps/backend-python/alembic/versions/`, atheneum CLAUDE.md "Migrations" section.
