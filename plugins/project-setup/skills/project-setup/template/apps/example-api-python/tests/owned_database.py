"""A throwaway database that one pytest-xdist worker owns, and the proof that it owns it.

The controller creates one per worker, as a copy of the migrated template database, and drops it
when the worker ends: pass, fail or crash. It drops only a database it created in this run. The
name must match NAME, and the database must still carry the OID and the comment it got when it was
created. A database that already has the name is never adopted, because CREATE DATABASE without
IF NOT EXISTS fails on it. A refusal raises and leaves the database where it is.
"""

import re
from dataclasses import dataclass, field
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from uuid import uuid4

import asyncpg

NAME = re.compile(r"test_gw[0-9]{1,3}_[0-9a-f]{32}")
WORKER = re.compile(r"gw[0-9]{1,3}")
IDENTIFIER = re.compile(r"[a-z_][a-z0-9_]{0,62}")
MARKER = "ctl-test-worker:"


def database_url(base: str, name: str) -> str:
    """<base> with its database replaced by <name>. Only a name in the owned pattern is accepted."""
    if not NAME.fullmatch(name):
        raise RuntimeError(f"refusing {name!r}: a worker database is named test_gw<n>_<32 hex>")
    parts = urlsplit(base)
    if parts.scheme not in ("postgres", "postgresql") or not parts.hostname:
        raise RuntimeError("a worker's server URL must be a postgresql:// URL with a host")
    # A database named in the query would win over the path, so it goes.
    query = [(k, v) for k, v in parse_qsl(parts.query) if k not in ("dbname", "database")]
    return urlunsplit(parts._replace(path="/" + name, query=urlencode(query)))


@dataclass
class OwnedDatabase:
    """Worker <worker>'s database on the server <base> reaches, copied from <template>.

    <base> is a URL of any other database on that server: the controller connects there to create
    and drop this one. The URL holds a password, so it never appears in repr or in a message.
    """

    base: str = field(repr=False)
    template: str
    worker: str
    name: str = ""
    marker: str = field(default="", repr=False)
    oid: int | None = None
    created: bool = False

    def __post_init__(self) -> None:
        if not WORKER.fullmatch(self.worker):
            raise RuntimeError(f"no worker database for {self.worker!r}: worker names are gw<n>")
        if not IDENTIFIER.fullmatch(self.template):
            raise RuntimeError(f"the template database name {self.template!r} is not a plain name")
        self.name = self.name or f"test_{self.worker}_{uuid4().hex}"
        self.marker = self.marker or MARKER + uuid4().hex

    @property
    def url(self) -> str:
        return database_url(self.base, self.name)

    async def _connect(self) -> asyncpg.Connection:
        """A connection to the base database. A failure is raised again without asyncpg's frames,
        because a traceback prints their arguments, and those hold the password."""
        try:
            return await asyncpg.connect(self.base, timeout=10)
        except Exception as problem:  # any connect failure; its type and message carry no password
            message = f"cannot reach the test database server of {self.worker}"
            raise RuntimeError(f"{message}: {type(problem).__name__}: {problem}") from None

    async def create(self) -> None:
        database_url(self.base, self.name)  # checks the name and the base before any SQL runs
        conn = await self._connect()
        try:
            # No IF NOT EXISTS: a database that already has this name is never adopted.
            await conn.execute(f'CREATE DATABASE "{self.name}" TEMPLATE "{self.template}"')
            self.created = True
            self.oid = await conn.fetchval(
                "SELECT oid FROM pg_database WHERE datname = $1", self.name
            )
            await conn.execute(f"COMMENT ON DATABASE \"{self.name}\" IS '{self.marker}'")
        finally:
            await conn.close()

    async def drop(self) -> None:
        """Drop the database, when this object created it and it is still that database."""
        if not self.created:
            return
        database_url(self.base, self.name)  # the name check holds for cleanup too
        conn = await self._connect()
        try:
            # A database comment lives in pg_shdescription, which every database on a server shares.
            row = await conn.fetchrow(
                "SELECT oid, shobj_description(oid, 'pg_database') AS marker"
                " FROM pg_database WHERE datname = $1",
                self.name,
            )
            if row is None:
                raise RuntimeError(f"the worker database {self.name} is gone; nothing to drop")
            if (row["oid"], row["marker"]) != (self.oid, self.marker):
                raise RuntimeError(
                    f"refusing to drop {self.name}: it does not carry the OID and the marker "
                    "this run gave it, so this run did not create it"
                )
            # FORCE ends the sessions in this one database, such as those of a crashed worker.
            await conn.execute(f'DROP DATABASE "{self.name}" WITH (FORCE)')
        finally:
            await conn.close()
        self.created = False
