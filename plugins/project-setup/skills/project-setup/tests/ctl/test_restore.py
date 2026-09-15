"""Restore ordering and failures; all engine behavior is simulated by recording shims."""

import os
from pathlib import Path

import pytest

from test_admin_runtime import sandbox


def archive(sandbox, content=b"PGDMPsynthetic archive\x00\xff"):
    directory = sandbox.root / "backups with spaces"
    directory.mkdir()
    if content is not None:
        (directory / "postgres.dump").write_bytes(content)
    (directory / "redis.rdb").write_bytes(b"synthetic redis")
    (directory / "neo4j-schema.cypher").write_text("synthetic schema;")
    return directory


def mutations(sandbox):
    return [action for action in sandbox.actions() if action in ("drop", "create", "restore", "stop", "copy", "start", "cypher")]


@pytest.mark.parametrize("content", [None, b"", b"plain SQL", b"not a custom archive"])
def test_missing_or_wrong_format_prevents_every_engine_mutation(sandbox, content):
    directory = archive(sandbox, content)
    sandbox.env["DATA_SVCS"] = "postgres redis neo4j"
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode != 0
    assert not mutations(sandbox)
    assert "list" not in sandbox.actions()


def test_unreadable_archive_prevents_mutation(sandbox):
    if os.geteuid() == 0:
        pytest.skip("root bypasses file read permission checks")
    directory = archive(sandbox)
    (directory / "postgres.dump").chmod(0)
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode != 0
    assert not mutations(sandbox)


def test_invalid_archive_list_failure_prevents_all_mutation(sandbox):
    directory = archive(sandbox)
    sandbox.env["DATA_SVCS"] = "postgres redis neo4j"
    sandbox.env["FAIL_ACTION"] = "list"
    assert sandbox.run("db", "restore", str(directory), "-y").returncode == 37
    assert sandbox.actions()[-1] == "list"
    assert not mutations(sandbox)


def test_valid_list_precedes_separate_quoted_drop_create_restore(sandbox, tmp_path):
    directory = archive(sandbox)
    database = '-weird "database; DROP DATABASE other; --'
    username = "operator with spaces"
    sandbox.env.update(POSTGRES_DB=database, POSTGRES_USER=username)
    result = sandbox.run("db", "restore", directory.name, "-y", cwd=tmp_path)
    assert result.returncode == 0, result.stderr
    records = [record for record in sandbox.records() if record["action"] in ("list", "drop", "create", "restore")]
    assert [record["action"] for record in records] == ["list", "drop", "create", "restore"]
    for record in records:
        assert "-T" in record["args"]
    assert records[1]["args"][-6:] == ["dropdb", "-U", username, "--if-exists", "--", database]
    assert records[2]["args"][-5:] == ["createdb", "-U", username, "--", database]
    assert records[3]["args"][-6:] == ["pg_restore", "-U", username, "-d", database, "--no-owner"]
    payload = (directory / "postgres.dump").read_bytes().decode("latin1")
    assert records[0]["stdin"] == records[3]["stdin"] == payload


@pytest.mark.parametrize("failure,expected", [("drop", ["drop"]), ("create", ["drop", "create"]), ("restore", ["drop", "create", "restore"])])
def test_postgres_failures_stop_later_engines(sandbox, failure, expected):
    directory = archive(sandbox)
    sandbox.env.update(DATA_SVCS="postgres redis neo4j", FAIL_ACTION=failure)
    assert sandbox.run("db", "restore", str(directory), "-y").returncode == 37
    assert mutations(sandbox) == expected


@pytest.mark.parametrize("service", ["api", "engine"])
def test_active_current_project_dependent_refuses(sandbox, service):
    directory = archive(sandbox)
    sandbox.services("postgres", service)
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode != 0
    assert f"{service} is running" in result.stderr
    assert "list" not in sandbox.actions()
    assert not mutations(sandbox)


def test_query_failure_refuses_before_preflight(sandbox):
    directory = archive(sandbox)
    sandbox.env["FAIL_ACTION"] = "ps"
    assert sandbox.run("db", "restore", str(directory), "-y").returncode != 0
    assert "list" not in sandbox.actions()
    assert not mutations(sandbox)


@pytest.mark.parametrize("modern", [False, True])
def test_active_recorded_host_process_refuses(sandbox, modern):
    directory = archive(sandbox)
    sandbox.env["LOGS_DIR"] = "custom logs"
    records = sandbox.root / "custom logs/run"
    records.mkdir(parents=True)
    if modern:
        record = records / "dev-api.process"
        record.mkdir()
        stat = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()
        (record / "pid").write_text(f"{os.getpid()} {stat[19]}\n")
    else:
        (records / "dev-api.pid").write_text(f"{os.getpid()}\n")
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode != 0
    assert "host dev process" in result.stderr
    assert not mutations(sandbox)


def test_stale_process_identity_does_not_block(sandbox):
    directory = archive(sandbox)
    record = sandbox.root / "logs/run/dev-api.process"
    record.mkdir(parents=True)
    (record / "pid").write_text(f"{os.getpid()} impossible-birth-time\n")
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode == 0, result.stderr


def test_confirmation_declined_after_list_changes_nothing(sandbox):
    directory = archive(sandbox)
    result = sandbox.run("db", "restore", str(directory), input="n\n")
    assert result.returncode == 0, result.stderr
    assert "list" in sandbox.actions()
    assert not mutations(sandbox)


@pytest.mark.parametrize("failure", [None, "stop", "copy", "start", "cypher"])
def test_redis_and_neo4j_behavior_and_error_propagation(sandbox, failure):
    directory = archive(sandbox)
    sandbox.env.update(DATA_SVCS="postgres redis neo4j", NEO4J_PASSWORD="synthetic pass", READ_CYPHER="1")
    if failure:
        sandbox.env["FAIL_ACTION"] = failure
    result = sandbox.run("db", "restore", str(directory), "-y")
    assert result.returncode == (37 if failure else 0), result.stderr
    expected = ["drop", "create", "restore", "stop", "copy", "start", "cypher"]
    assert mutations(sandbox) == (expected[:expected.index(failure) + 1] if failure else expected)
    if not failure:
        copy = next(record for record in sandbox.records() if record["action"] == "copy")
        assert copy["args"] == ["cp", str(directory / "redis.rdb"), "fixture-redis-id:/data/dump.rdb"]
        assert sandbox.records()[-1]["stdin"] == "synthetic schema;"


def test_missing_redis_container_does_not_stop_or_copy(sandbox):
    directory = archive(sandbox, None)
    sandbox.env.update(DATA_SVCS="redis", REDIS_ID="")
    assert sandbox.run("db", "restore", str(directory), "-y").returncode != 0
    assert not mutations(sandbox)


@pytest.mark.parametrize("failure", [None, "dump", "redis", "ps", "copy"])
def test_backup_resolves_storage_before_creation_and_propagates_failures(sandbox, failure, tmp_path):
    (sandbox.root / ".env").write_text("COMPOSE_PROJECT_NAME=fixture\nLOGS_DIR=relative logs\nBACKUP_DIR=${LOGS_DIR}/snapshots\n")
    sandbox.env["DATA_SVCS"] = "postgres redis"
    if failure:
        sandbox.env["FAIL_ACTION"] = failure
    result = sandbox.run("db", "backup", cwd=tmp_path)
    assert result.returncode == (37 if failure else 0), result.stderr
    destinations = list((sandbox.root / "relative logs/snapshots").glob("*"))
    assert len(destinations) == 1
    assert not (tmp_path / "relative logs").exists()
    if failure:
        assert sandbox.actions()[-1] == failure
    else:
        assert (destinations[0] / "postgres.dump").read_bytes().startswith(b"PGDMP")


def test_backup_neo4j_pipeline_failure_propagates(sandbox):
    sandbox.env.update(DATA_SVCS="neo4j", NEO4J_PASSWORD="synthetic pass", FAIL_ACTION="exec")
    assert sandbox.run("db", "backup").returncode == 37
