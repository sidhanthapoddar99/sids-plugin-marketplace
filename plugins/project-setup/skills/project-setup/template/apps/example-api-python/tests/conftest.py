"""The database fixture of the api's tests.

ctl test gives this suite its own database, a copy of the migrated test_template, in
TEST_DATABASE_URL. On more than one worker, worker_database.py gives each pytest-xdist worker a
database of its own on a server of its own, and points TEST_DATABASE_URL at it. Read it in a
fixture, as below, never at import: a worker imports this file before it learns its database.
"""

import os
from collections.abc import AsyncIterator
from urllib.parse import urlsplit

import asyncpg
import pytest

pytest_plugins = ["worker_database"]


async def connect(url: str) -> asyncpg.Connection:
    """A connection to <url>. A failure fails the test with a message alone, because a traceback
    prints the arguments of asyncpg's frames, and those hold the password."""
    try:
        return await asyncpg.connect(url, timeout=60)
    except Exception as problem:  # any connect failure; its type and message carry no password
        parts = urlsplit(url)
        where = f"{parts.hostname}:{parts.port}{parts.path}"
        reason = f"{type(problem).__name__}: {problem}"
        pytest.fail(f"cannot connect to the test database {where}: {reason}", pytrace=False)


@pytest.fixture
async def conn() -> AsyncIterator[asyncpg.Connection]:
    """A connection to this process's test database, inside a transaction the test never commits,
    so the next test sees the migrated schema and nothing an earlier test wrote."""
    url = os.environ.get("TEST_DATABASE_URL", "")
    if not url:
        pytest.fail(
            "TEST_DATABASE_URL is not set: run this suite through `ctl test`, "
            "which starts its database",
            pytrace=False,
        )
    connection = await connect(url)
    transaction = connection.transaction()
    await transaction.start()
    try:
        yield connection
    finally:
        await transaction.rollback()
        await connection.close()
