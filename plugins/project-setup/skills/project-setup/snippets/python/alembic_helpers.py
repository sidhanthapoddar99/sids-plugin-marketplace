"""Alembic shim helper — runs a sibling .sql file from a .py revision.

Place at apps/backend/alembic_helpers.py (importable by alembic env.py PYTHONPATH).
"""
from pathlib import Path

from alembic import op


def run_sql(py_file: str, suffix: str) -> None:
    """Execute the .sql file sibling to the given .py revision file.

    Usage in a revision file:
        from alembic_helpers import run_sql

        def upgrade() -> None: run_sql(__file__, ".up.sql")
        def downgrade() -> None: run_sql(__file__, ".down.sql")
    """
    sql_path = Path(py_file).with_suffix(suffix)
    if not sql_path.exists():
        # empty .down.sql is fine for forward-only migrations
        return
    sql = sql_path.read_text()
    if not sql.strip():
        return
    op.execute(sql)
