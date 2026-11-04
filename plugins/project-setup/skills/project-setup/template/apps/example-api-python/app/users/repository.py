"""SQL for users. Every function takes a connection; the caller owns the transaction.
No rules, no HTTP.

The reserved `default` row comes only from the migration V3__development_identity.sql: read it by
app.core.auth.RESERVED_USER_ID, and never insert, update or delete it here.
"""

from uuid import UUID

from asyncpg import Connection, Record


async def create(conn: Connection, username: str, password_hash: str | None) -> Record:
    """A new account. A username already taken raises asyncpg.UniqueViolationError."""
    row = await conn.fetchrow(
        "INSERT INTO users (username, password_hash) VALUES ($1, $2)"
        " RETURNING id, username, password_hash, development_identity, created_at",
        username,
        password_hash,
    )
    if row is None:
        raise RuntimeError("INSERT … RETURNING gave no row")
    return row


async def by_id(conn: Connection, user_id: UUID) -> Record | None:
    return await conn.fetchrow(
        "SELECT id, username, password_hash, development_identity, created_at"
        " FROM users WHERE id = $1",
        user_id,
    )


async def by_username(conn: Connection, username: str) -> Record | None:
    return await conn.fetchrow(
        "SELECT id, username, password_hash, development_identity, created_at"
        " FROM users WHERE username = $1",
        username,
    )
