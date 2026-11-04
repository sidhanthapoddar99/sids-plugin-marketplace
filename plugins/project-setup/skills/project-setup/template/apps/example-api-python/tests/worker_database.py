"""One database per pytest-xdist worker, on that worker's own PostgreSQL server.

ctl test runs a suite marked `db workers` with `-n <workers>`, starts one server per worker, and
lists one URL per server in TEST_DATABASE_URLS, in worker order. Before worker gw<n> starts, the
controller creates an OwnedDatabase for it on server n, a copy of TEST_DATABASE_TEMPLATE, and hands
the URL over in workerinput. The worker points TEST_DATABASE_URL and the other database settings at
it. The controller drops it when the worker ends, a crashed worker included, and drops any left when
the run ends. SIGTERM interrupts the run the way Ctrl-C does, so a stopped run cleans up as well.

One server per worker, because Docker Desktop forwards each connection to a published port through
a new connection from its VM, which has about 10,500 source ports per container address, each held
60 s after a close. Several workers that open connections fast run one server's ports out.

A serial run is untouched: no worker starts, and the suite reads the TEST_DATABASE_URL ctl gave it.
On several workers, ctl's DATABASE_URL, TEST_DATABASE_URL and POSTGRES_DB name a database no server
has until this plugin points them at the worker's own, so a test reads them in a fixture, not when
a conftest is imported: a worker imports its conftests before it learns its database.
"""

import asyncio
import os
import signal
from urllib.parse import urlsplit

import pytest
from owned_database import WORKER, OwnedDatabase

OWNED = pytest.StashKey[dict[str, OwnedDatabase]]()
FAILED = pytest.StashKey[list[str]]()
SIGTERM = pytest.StashKey[object]()


def worker_index(worker: str, servers: int) -> int:
    """The server of worker gw<n>: n, the entry it takes in TEST_DATABASE_URLS, of <servers>.
    It takes a count, not the URLs, because a traceback prints a function's arguments."""
    if not WORKER.fullmatch(worker):
        raise RuntimeError(
            f"cannot choose a test database server for the pytest-xdist worker {worker!r}: "
            "worker names are gw<n>, and worker gw<n> takes entry n of TEST_DATABASE_URLS"
        )
    index = int(worker[2:])
    if index >= servers:
        raise RuntimeError(
            f"worker {worker} has no test database server: TEST_DATABASE_URLS lists "
            f"{servers}. Run the suite through `ctl test`, which starts one server per worker"
        )
    return index


def point_at(url: str) -> None:
    """Make <url> this process's test database, under every name ctl gives a suite."""
    parts = urlsplit(url)
    os.environ.update(
        DATABASE_URL=url,
        TEST_DATABASE_URL=url,
        POSTGRES_HOST=parts.hostname or "",
        POSTGRES_PORT=str(parts.port or 5432),
        POSTGRES_DB=parts.path.lstrip("/"),
    )


def _interrupt(signum: int, frame: object) -> None:
    raise KeyboardInterrupt("SIGTERM")


def pytest_configure(config: pytest.Config) -> None:
    workerinput = getattr(config, "workerinput", None)
    if workerinput is not None:
        if "test_database_url" not in workerinput:
            raise RuntimeError(
                f"worker {workerinput.get('workerid')} got no database: the controller did not run "
                "pytest_configure_node of worker_database.py"
            )
        point_at(workerinput["test_database_url"])
        return
    config.stash[OWNED] = {}
    config.stash[FAILED] = []
    if config.getoption("numprocesses", None):
        config.stash[SIGTERM] = signal.signal(signal.SIGTERM, _interrupt)


@pytest.hookimpl(optionalhook=True)
def pytest_configure_node(node) -> None:  # node: xdist's WorkerController
    template = os.environ.get("TEST_DATABASE_TEMPLATE", "")
    if not template:
        raise RuntimeError(
            "TEST_DATABASE_TEMPLATE is not set, so a worker has no database to copy. "
            "Run the suite through `ctl test`"
        )
    worker = node.gateway.id
    servers = os.environ.get("TEST_DATABASE_URLS", "").split()
    owned = OwnedDatabase(servers[worker_index(worker, len(servers))], template, worker)
    # Recorded before it exists, so cleanup sees a create that fails halfway. A database created
    # without its OID or marker is then refused, reported at the end and left on the server.
    node.config.stash[OWNED][worker] = owned
    asyncio.run(owned.create())
    node.workerinput["test_database_url"] = owned.url


@pytest.hookimpl(optionalhook=True)
def pytest_testnodedown(node, error: object) -> None:
    drop(node.config, node.gateway.id)


def drop(config: pytest.Config, worker: str) -> None:
    """Drop the worker's database. A failure is kept for the end of the run, not raised here,
    because the other workers' databases still need their turn."""
    owned = config.stash[OWNED].pop(worker, None)
    if owned is None:
        return
    try:
        asyncio.run(owned.drop())
    except Exception as problem:  # every failure is reported at the end of the run
        config.stash[FAILED].append(f"{owned.name}: {problem}")


# Last, so a refused cleanup that raises here still lets every other plugin unconfigure first.
@pytest.hookimpl(trylast=True)
def pytest_unconfigure(config: pytest.Config) -> None:
    owned = config.stash.get(OWNED, None)
    if hasattr(config, "workerinput") or owned is None:
        return
    for worker in list(owned):
        drop(config, worker)
    previous = config.stash.get(SIGTERM, None)
    if previous is not None:
        signal.signal(signal.SIGTERM, previous)  # type: ignore[arg-type]
    failed = config.stash[FAILED]
    if failed:
        raise RuntimeError("worker database cleanup failed: " + "; ".join(failed))
