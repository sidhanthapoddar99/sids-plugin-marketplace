"""The api example's database per pytest-xdist worker: tests/owned_database.py, worker_database.py
and the connect of conftest.py.

The example's own suite needs PostgreSQL, so these tests run its code against a fake asyncpg that
keeps a catalog per server in a JSON file. They prove that a worker database is a copy of the
template, that cleanup drops only a database this run created and refuses any other, that worker
gw<n> takes server n and any other name fails, that a worker without a database fails, and that no
URL password shows, a failed connect included. The last two run a real pytest-xdist session in a
scratch folder, and skip by name when pytest-xdist is not installed: a worker that crashes and a
run stopped with SIGTERM both drop every worker database.
"""

import importlib
import importlib.util
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

TESTS = Path(__file__).resolve().parents[2] / "template/apps/example-api-python/tests"
SECRET = "s3cret-pw"
SERVERS = [f"postgresql://test:{SECRET}@127.0.0.1:{port}/test_api" for port in (23456, 23457)]

# The fake driver. connect() reaches a server by host:port and needs the database to exist there.
# CREATE, COMMENT and DROP DATABASE change the server's catalog; the two catalog reads answer from it.
FAKE_ASYNCPG = r'''
import json, os, re
from urllib.parse import urlsplit

def _load():
    with open(os.environ["FAKE_PG_CATALOG"]) as f:
        return json.load(f)

def _save(state):
    with open(os.environ["FAKE_PG_CATALOG"], "w") as f:
        json.dump(state, f)

class Connection:
    def __init__(self, server):
        self.server = server

    async def execute(self, sql):
        state = _load(); dbs = state["servers"][self.server]
        if m := re.fullmatch(r'CREATE DATABASE "([^"]+)" TEMPLATE "([^"]+)"', sql):
            if m[2] not in dbs: raise RuntimeError("template does not exist")
            if m[1] in dbs: raise RuntimeError(f'database "{m[1]}" already exists')
            state["oid"] += 1; dbs[m[1]] = [state["oid"], None]
        elif m := re.fullmatch(r"""COMMENT ON DATABASE "([^"]+)" IS '([^']*)'""", sql):
            dbs[m[1]][1] = m[2]
        elif m := re.fullmatch(r'DROP DATABASE "([^"]+)" WITH \(FORCE\)', sql):
            del dbs[m[1]]
        else:
            raise RuntimeError(f"the fake does not know: {sql}")
        state["log"].append([self.server, sql]); _save(state)

    async def fetchval(self, sql, name):
        assert sql == "SELECT oid FROM pg_database WHERE datname = $1"
        return _load()["servers"][self.server][name][0]

    async def fetchrow(self, sql, name):
        assert "shobj_description(oid, 'pg_database') AS marker" in sql
        row = _load()["servers"][self.server].get(name)
        return None if row is None else {"oid": row[0], "marker": row[1]}

    async def close(self):
        pass

async def connect(dsn, timeout=None):
    parts = urlsplit(dsn)
    server = f"{parts.hostname}:{parts.port}"
    state = _load(); state["connects"].append(server); _save(state)
    if parts.path.lstrip("/") not in state["servers"][server]:
        raise RuntimeError("database does not exist")
    return Connection(server)
'''


def seed(path: Path) -> None:
    servers = {f"127.0.0.1:{port}": {"test_api": [1, None], "test_template": [2, None]} for port in (23456, 23457)}
    path.write_text(json.dumps({"servers": servers, "oid": 100, "log": [], "connects": []}))


@pytest.fixture
def catalog(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """The fake driver installed in place of asyncpg, and the example's two modules imported."""
    (tmp_path / "fakes").mkdir()
    (tmp_path / "fakes/asyncpg.py").write_text(FAKE_ASYNCPG)
    path = tmp_path / "catalog.json"
    seed(path)
    monkeypatch.setenv("FAKE_PG_CATALOG", str(path))
    # The modules come from the shipped template, so no bytecode may land beside them.
    monkeypatch.setattr(sys, "dont_write_bytecode", True)
    monkeypatch.syspath_prepend(str(tmp_path / "fakes"))
    monkeypatch.syspath_prepend(str(TESTS))
    for name in ("asyncpg", "owned_database", "worker_database"):
        monkeypatch.delitem(sys.modules, name, raising=False)
    owned = importlib.import_module("owned_database")
    worker = importlib.import_module("worker_database")
    # Under its own name, because this folder's pytest session may hold a module named conftest.
    spec = importlib.util.spec_from_file_location("api_conftest", TESTS / "conftest.py")
    assert spec is not None and spec.loader is not None
    conftest = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(conftest)
    yield SimpleNamespace(read=lambda: json.loads(path.read_text()), owned=owned, worker=worker,
                          conftest=conftest, path=path)
    for name in ("asyncpg", "owned_database", "worker_database"):
        sys.modules.pop(name, None)


def run(coroutine):
    import asyncio

    return asyncio.run(coroutine)


def test_a_worker_database_is_a_copy_of_the_template_and_cleanup_drops_it(catalog) -> None:
    owned = catalog.owned.OwnedDatabase(SERVERS[1], "test_template", "gw1")
    run(owned.create())
    assert catalog.owned.NAME.fullmatch(owned.name) and owned.name.startswith("test_gw1_")
    state = catalog.read()
    oid, marker = state["servers"]["127.0.0.1:23457"][owned.name]
    assert (oid, marker) == (owned.oid, owned.marker) and marker.startswith("ctl-test-worker:")
    assert state["log"][0] == ["127.0.0.1:23457", f'CREATE DATABASE "{owned.name}" TEMPLATE "test_template"']
    assert owned.url == f"postgresql://test:{SECRET}@127.0.0.1:23457/{owned.name}"
    run(owned.drop())
    assert owned.name not in catalog.read()["servers"]["127.0.0.1:23457"]
    run(owned.drop())  # a second cleanup has nothing left to do


@pytest.mark.parametrize("change", ["marker", "oid"])
def test_cleanup_refuses_a_database_it_did_not_create(catalog, change: str) -> None:
    owned = catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "gw0")
    run(owned.create())
    # Someone else's database under the same name: another marker, or dropped and created again.
    state = catalog.read()
    row = state["servers"]["127.0.0.1:23456"][owned.name]
    row[1 if change == "marker" else 0] = "ctl-test-worker:someone-else" if change == "marker" else 999
    catalog.path.write_text(json.dumps(state))
    with pytest.raises(RuntimeError, match="refusing to drop .* this run did not create it"):
        run(owned.drop())
    assert owned.name in catalog.read()["servers"]["127.0.0.1:23456"]
    assert not any(sql.startswith("DROP") for _, sql in catalog.read()["log"])


def test_a_database_that_already_has_the_name_is_never_adopted(catalog) -> None:
    owned = catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "gw0")
    state = catalog.read()
    state["servers"]["127.0.0.1:23456"][owned.name] = [7, None]
    catalog.path.write_text(json.dumps(state))
    with pytest.raises(RuntimeError, match="already exists"):
        run(owned.create())
    assert not owned.created
    run(owned.drop())
    assert catalog.read()["servers"]["127.0.0.1:23456"][owned.name] == [7, None]


def test_a_name_outside_the_pattern_is_refused_before_any_sql(catalog) -> None:
    for name in ("test_api", "postgres", "test_gw0_short", 'test_gw0_' + "0" * 31 + '"'):
        owned = catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "gw0", name=name, created=True)
        with pytest.raises(RuntimeError, match="refusing"):
            run(owned.create())
        with pytest.raises(RuntimeError, match="refusing"):
            run(owned.drop())
    with pytest.raises(RuntimeError, match="worker names are gw<n>"):
        catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "master")
    with pytest.raises(RuntimeError, match="not a plain name"):
        catalog.owned.OwnedDatabase(SERVERS[0], 'x" TEMPLATE "y', "gw0")
    assert catalog.read()["connects"] == []


def test_worker_gw_n_takes_server_n_and_any_other_name_fails(catalog) -> None:
    index = catalog.worker.worker_index
    assert [index(f"gw{n}", 2) for n in range(2)] == [0, 1]
    for name in ("master", "worker-1", "gw", "gw1a"):
        with pytest.raises(RuntimeError, match="worker names are gw<n>"):
            index(name, 2)
    with pytest.raises(RuntimeError, match="worker gw2 has no test database server: TEST_DATABASE_URLS lists 2"):
        index("gw2", 2)


def test_a_worker_without_a_database_fails_instead_of_reading_the_shared_settings(catalog) -> None:
    with pytest.raises(RuntimeError, match="worker gw0 got no database"):
        catalog.worker.pytest_configure(SimpleNamespace(workerinput={"workerid": "gw0"}))


def test_a_failed_connect_shows_no_password(catalog) -> None:
    # The fake driver refuses a database the server lacks, as PostgreSQL does, inside a frame
    # whose argument is the URL.
    gone = SERVERS[0].rsplit("/", 1)[0] + "/test_worker_database_not_set"
    with pytest.raises(pytest.fail.Exception) as failure:
        run(catalog.conftest.connect(gone))
    assert failure.value.pytrace is False
    assert str(failure.value).startswith("cannot connect to the test database 127.0.0.1:23456/test_worker_database_not_set:")
    assert SECRET not in str(failure.value)
    # The worker's own connect raises again without asyncpg's frames, so a long traceback,
    # arguments included, holds no password either.
    state = catalog.read()
    del state["servers"]["127.0.0.1:23456"]["test_api"]
    catalog.path.write_text(json.dumps(state))
    with pytest.raises(RuntimeError, match="cannot reach the test database server of gw0") as refusal:
        run(catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "gw0").create())
    assert refusal.value.__suppress_context__
    assert SECRET not in str(refusal.getrepr(style="long", funcargs=True, chain=True))


def test_no_password_shows_in_a_repr_or_a_refusal(catalog) -> None:
    owned = catalog.owned.OwnedDatabase(SERVERS[0], "test_template", "gw0")
    assert SECRET not in repr(owned)
    run(owned.create())
    state = catalog.read()
    state["servers"]["127.0.0.1:23456"][owned.name][1] = "other"
    catalog.path.write_text(json.dumps(state))
    with pytest.raises(RuntimeError) as refusal:
        run(owned.drop())
    assert SECRET not in str(refusal.value)


def test_a_failed_cleanup_is_reported_at_the_end_after_the_others_drop(catalog) -> None:
    config = SimpleNamespace(stash=pytest.Stash(), option=SimpleNamespace())
    config.stash[catalog.worker.OWNED] = {}
    config.stash[catalog.worker.FAILED] = []
    for n in range(2):
        owned = catalog.owned.OwnedDatabase(SERVERS[n], "test_template", f"gw{n}")
        run(owned.create())
        config.stash[catalog.worker.OWNED][f"gw{n}"] = owned
    kept = config.stash[catalog.worker.OWNED]["gw0"].name
    state = catalog.read()
    state["servers"]["127.0.0.1:23456"][kept][1] = "other"
    catalog.path.write_text(json.dumps(state))
    with pytest.raises(RuntimeError, match=f"worker database cleanup failed: {kept}: refusing"):
        catalog.worker.pytest_unconfigure(config)
    servers = catalog.read()["servers"]
    assert kept in servers["127.0.0.1:23456"]
    assert not [name for name in servers["127.0.0.1:23457"] if name.startswith("test_gw")]


# A real pytest-xdist session over the example's tests/ folder: its conftest, its plugin, the fake
# driver, and test files that pass, crash their worker, or wait to be stopped.


def xdist_session(tmp_path: Path, files: dict[str, str]):
    pytest.importorskip("xdist", reason="pytest-xdist is not installed; the session tests need it")
    app = tmp_path / "app"
    shutil.copytree(TESTS, app / "tests", ignore=shutil.ignore_patterns("test_*.py", "__pycache__"))
    for name, text in files.items():
        (app / "tests" / name).write_text(text)
    (tmp_path / "fakes").mkdir()
    (tmp_path / "fakes/asyncpg.py").write_text(FAKE_ASYNCPG)
    seed(tmp_path / "catalog.json")
    env = {key: value for key, value in os.environ.items() if not key.startswith(("PYTEST_", "TEST_DATABASE"))}
    env.update(PYTHONPATH=str(tmp_path / "fakes"), FAKE_PG_CATALOG=str(tmp_path / "catalog.json"),
               TEST_DATABASE_URLS=" ".join(SERVERS), TEST_DATABASE_TEMPLATE="test_template", STARTED=str(tmp_path / "started"))
    command = [sys.executable, "-m", "pytest", "-p", "no:cacheprovider", "-n", "2", "--dist", "loadfile", "--max-worker-restart", "0"]
    return app, env, command, lambda: json.loads((tmp_path / "catalog.json").read_text())


def worker_databases(state) -> list[str]:
    return [name for dbs in state["servers"].values() for name in dbs if name.startswith("test_gw")]


def test_a_crashed_worker_fails_the_run_and_its_database_is_dropped(tmp_path: Path) -> None:
    app, env, command, read = xdist_session(tmp_path, {
        "test_passes.py": "def test_passes():\n    pass\n",
        "test_crashes.py": "import os\n\ndef test_crashes():\n    os._exit(3)\n"})
    result = subprocess.run(command, cwd=app, env=env, capture_output=True, text=True, timeout=120, check=False)
    output = result.stdout + result.stderr
    assert result.returncode != 0, output
    assert "crashed" in output
    state = read()
    created = [(server, sql) for server, sql in state["log"] if sql.startswith("CREATE")]
    assert sorted(server for server, _ in created) == ["127.0.0.1:23456", "127.0.0.1:23457"], output
    assert '"test_gw0_' in dict(created)["127.0.0.1:23456"] and '"test_gw1_' in dict(created)["127.0.0.1:23457"]
    assert worker_databases(state) == [], output
    assert SECRET not in output


def test_a_run_stopped_with_sigterm_drops_every_worker_database(tmp_path: Path) -> None:
    waits = "import os, time\n\ndef test_waits():\n    open(os.environ['STARTED'] + '-' + os.environ['PYTEST_XDIST_WORKER'], 'w').close()\n    time.sleep(60)\n"
    app, env, command, read = xdist_session(tmp_path, {"test_waits_a.py": waits, "test_waits_b.py": waits})
    session = subprocess.Popen(command, cwd=app, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    deadline = time.monotonic() + 60
    while len(list(tmp_path.glob("started-gw*"))) < 2:
        assert session.poll() is None and time.monotonic() < deadline, "the workers did not start their tests"
        time.sleep(0.1)
    assert len(worker_databases(read())) == 2
    session.send_signal(signal.SIGTERM)
    output, _ = session.communicate(timeout=60)
    assert session.returncode != 0
    assert worker_databases(read()) == [], output
