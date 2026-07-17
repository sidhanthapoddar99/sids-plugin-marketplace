# Raw-SQL recipe — mechanics

Mechanics for the **Alembic + raw-SQL shim** style: schema authored in raw `.sql` files, run by Alembic through a 3-line Python shim per migration. Zero decisions here — **when** to choose this style (multi-language schema consumers, hand-tuned DDL, DBAs in the loop) is owned by `references/3-app/04-database/01_migrations.md`. This file is the "how". Base Alembic setup (`env.py`, `alembic.ini`, entrypoint) is shared with `references/3-app/04-database/02_alembic-recipe.md`.

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

DBAs, operators, and `sqlx` all read this file directly — there's no ORM intermediary.

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

Generates the `.py` shim + empty `.up.sql` and `.down.sql`, ready to fill.

## The cross-language drift check

After every migration, regenerate the consuming language's offline metadata. For Rust's `sqlx`:

```bash
ctl sqlx-prepare
```

which runs:

```bash
( cd apps/backend-rust && DATABASE_URL="${DATABASE_URL}" cargo sqlx prepare --workspace )
```

This writes the `.sqlx/` files Rust uses for offline query verification. `ctl` runs the three steps in order on every invocation:

```
migrate up → sqlx prepare --check → cargo build
```

Drift fails locally before code lands. **The rule:** the consuming language never writes DDL — if a Rust query needs a column, write the Alembic migration first, then regenerate `.sqlx/`, then add the query.

## Anti-patterns

- Writing the `.up.sql` and forgetting the shim — Alembic won't apply it.
- `op.execute` blocks inside the Python shim — defeats the source-of-truth split; the SQL belongs in the `.sql` file.
- `.down.sql` left silently empty — at least comment why it's forward-only.

## See also

- `references/3-app/04-database/01_migrations.md` — when to choose this style (and the run-model decision)
- `references/3-app/04-database/02_alembic-recipe.md` — the shared Alembic base (`env.py`, `alembic.ini`, entrypoint)
- `references/3-app/02-backend/02_two-plane-split.md` — when two backends share one DB, these files live in a neutral `apps/db` app
- `references/4-feature/types-and-contracts.md` — the per-consumer DTO rules (each language declares its own against the schema)
- `references/handoffs/examples-registry.md` — cite a registered repo using this pattern if one exists
