"""<message> — see .up.sql for the actual DDL.

Revision ID: <REVISION_ID>
Revises: <PARENT_REVISION>
Create Date: <DATE>
"""
# Alembic three-file pattern (atheneum-style):
#   <name>.py        — this shim (loads .up.sql / .down.sql)
#   <name>.up.sql    — the actual DDL (source of truth)
#   <name>.down.sql  — rollback (may be empty for forward-only)

from alembic_helpers import run_sql

revision = "<REVISION_ID>"
down_revision = "<PARENT_REVISION>"
branch_labels = None
depends_on = None


def upgrade() -> None:
    run_sql(__file__, ".up.sql")


def downgrade() -> None:
    run_sql(__file__, ".down.sql")
