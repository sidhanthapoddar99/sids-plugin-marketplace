"""The reserved `default` user, as the migrations create it and the database guards it."""

import asyncpg
import pytest

from app.core.auth import RESERVED_USER_ID
from app.users import repository


async def test_the_migrations_create_the_reserved_user(conn: asyncpg.Connection) -> None:
    row = await repository.by_id(conn, RESERVED_USER_ID)
    assert row is not None
    assert row["username"] == "default"
    assert row["development_identity"] is True and row["password_hash"] is None


async def test_the_reserved_user_can_never_hold_a_password(conn: asyncpg.Connection) -> None:
    with pytest.raises(asyncpg.CheckViolationError):
        await conn.execute("UPDATE users SET password_hash = 'x' WHERE id = $1", RESERVED_USER_ID)


async def test_no_other_account_can_carry_the_marker(conn: asyncpg.Connection) -> None:
    with pytest.raises(asyncpg.CheckViolationError):
        await conn.execute(
            "INSERT INTO users (username, development_identity) VALUES ('mallory', true)"
        )
