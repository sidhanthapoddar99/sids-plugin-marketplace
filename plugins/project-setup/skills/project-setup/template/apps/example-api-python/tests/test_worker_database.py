"""Each pytest-xdist worker reads a database of its own; a serial run reads the one ctl gave it."""

import os
from urllib.parse import urlsplit

import asyncpg
from owned_database import NAME


async def test_this_process_reads_its_own_database(
    conn: asyncpg.Connection, worker_id: str
) -> None:
    name = await conn.fetchval("SELECT current_database()")
    assert name == urlsplit(os.environ["TEST_DATABASE_URL"]).path.lstrip("/")
    if worker_id != "master":
        assert NAME.fullmatch(name) and name.startswith(f"test_{worker_id}_")
