"""The users repository against this process's own migrated database."""

import asyncpg
import pytest

from app.users import repository


async def test_a_new_account_reads_back_by_name_and_by_id(conn: asyncpg.Connection) -> None:
    created = await repository.create(conn, "ada", "a-password-hash")
    assert created["development_identity"] is False
    by_name = await repository.by_username(conn, "ada")
    assert by_name is not None and by_name["id"] == created["id"]
    by_id = await repository.by_id(conn, created["id"])
    assert by_id is not None and by_id["username"] == "ada"


async def test_an_account_may_have_no_password(conn: asyncpg.Connection) -> None:
    created = await repository.create(conn, "grace", None)
    assert created["password_hash"] is None


async def test_a_username_is_taken_once(conn: asyncpg.Connection) -> None:
    await repository.create(conn, "linus", None)
    with pytest.raises(asyncpg.UniqueViolationError):
        await repository.create(conn, "linus", None)


async def test_an_unknown_account_reads_as_none(conn: asyncpg.Connection) -> None:
    assert await repository.by_username(conn, "nobody") is None
