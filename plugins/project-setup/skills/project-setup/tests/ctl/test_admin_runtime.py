"""Runtime routing with synthetic recording shims; Docker behavior is simulated."""

import json
import os
import pty
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
SHIM = r'''
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
tool = Path(sys.argv[0]).name
action = tool
payload = ""
if tool == "uv" and args == ["--version"]:
    action = "uv-version"
if tool == "docker":
    if args == ["info"]:
        action = "info"
    elif args == ["compose", "version"]:
        action = "version"
    elif args[:1] == ["cp"]:
        action = "copy"
    elif args[:1] == ["inspect"]:
        action = "unrelated-inspect"
    else:
        assert args[0] == "compose", args
        assert args[args.index("--project-directory") + 1] == os.environ["CTL_ROOT"]
        command = args[args.index("-f") + 2:]
        action = command[0]
        if action == "exec":
            if "pg_restore" in command:
                action = "list" if "--list" in command else "restore"
                payload = sys.stdin.buffer.read().decode("latin1")
            elif "dropdb" in command:
                action = "drop"
            elif "createdb" in command:
                action = "create"
            elif "pg_dump" in command:
                action = "dump"
            elif "manager.py" in command:
                action = "manager"
            elif "cypher-shell" in command and "--format" not in command:
                action = "cypher"
                if os.environ.get("READ_CYPHER"):
                    payload = sys.stdin.read()
            elif "redis-cli" in command:
                action = "redis"
        elif action == "run":
            action = "neo4j-init" if "neo4j-init" in command else "migration"
record = {"tool": tool, "args": args, "action": action, "stdin": payload, "cwd": os.getcwd()}
with open(os.environ["RECORD"], "a") as output:
    output.write(json.dumps(record) + "\n")
if action == os.environ.get("FAIL_ACTION"):
    sys.exit(37)
if action == "ps":
    if "--services" in command:
        project = os.environ.get("COMPOSE_PROJECT_NAME", "fixture")
        services = json.loads(os.environ.get("PROJECT_SERVICES", "{}"))
        print("\n".join(services.get(project, [])))
    else:
        print(os.environ.get("REDIS_ID", "fixture-redis-id"))
elif action == "unrelated-inspect":
    print("running")
elif action == "dump":
    sys.stdout.write("PGDMPsynthetic archive")
'''


class RuntimeSandbox:
    def __init__(self, root: Path):
        self.root = root
        root.mkdir()
        shutil.copytree(TEMPLATE / "scripts", root / "scripts")
        shutil.copyfile(TEMPLATE / "ctl", root / "ctl")
        (root / ".env").write_text("COMPOSE_PROJECT_NAME=fixture\n")
        (root / "docker").mkdir()
        (root / "docker/compose.base.yaml").write_text("services: {}\n")
        binaries = root / "bin"
        binaries.mkdir()
        for name in ("docker", "uv"):
            executable = binaries / name
            executable.write_text(f"#!{sys.executable}\n" + SHIM)
            executable.chmod(0o755)
        self.env = {
            "PATH": f"{binaries}:{os.environ['PATH']}",
            "HOME": str(root),
            "CTL_ROOT": str(root),
            "RECORD": str(root / "record.jsonl"),
            "NO_COLOR": "1",
            "DATA_SVCS": "postgres",
            "PROJECT_SERVICES": json.dumps({"fixture": ["postgres"], "unrelated": ["api", "postgres"]}),
        }

    def services(self, *services: str):
        self.env["PROJECT_SERVICES"] = json.dumps({"fixture": services, "unrelated": ["api", "postgres"]})

    def host_manager(self):
        directory = self.root / "apps/example-api-python"
        directory.mkdir(parents=True)
        (directory / "manager.py").write_text("")

    def mode(self, mode: str):
        worker = self.root / "scripts/admin/manage.sh"
        worker.write_text(worker.read_text().replace('ADMIN_RUNTIME="auto"', f'ADMIN_RUNTIME="{mode}"'))

    def run(self, *args: str, tty: bool = False, cwd: Path | None = None, input: str = ""):
        command = ["bash", str(self.root / "ctl"), *args]
        if tty:
            master, slave = pty.openpty()
            try:
                return subprocess.run(command, env=self.env, cwd=cwd, stdin=slave, stdout=slave,
                                      stderr=subprocess.PIPE, text=True, timeout=15, check=False)
            finally:
                os.close(master)
                os.close(slave)
        return subprocess.run(command, env=self.env, cwd=cwd, input=input, capture_output=True,
                              text=True, timeout=15, check=False)

    def records(self):
        path = Path(self.env["RECORD"])
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def actions(self):
        return [record["action"] for record in self.records()]


@pytest.fixture
def sandbox(tmp_path):
    return RuntimeSandbox(tmp_path / "project with spaces")


def test_running_project_container_needs_no_host_manager(sandbox):
    sandbox.services("api", "postgres")
    args = ["settings", "set", "welcome", '{"text": "hello world", "literal": "$(false)"}']
    result = sandbox.run("manage", *args)
    assert result.returncode == 0, result.stderr
    record = sandbox.records()[-1]
    assert record["args"][-(len(args) + 5):] == ["exec", "-T", "api", "python", "manager.py", *args]
    assert "uv" not in sandbox.actions()
    assert "unrelated-inspect" not in sandbox.actions()


@pytest.mark.parametrize("failure", [None, "info", "version"])
def test_host_fallback_preserves_arguments_and_ignores_other_project(sandbox, failure):
    sandbox.host_manager()
    if failure:
        sandbox.env["FAIL_ACTION"] = failure
    result = sandbox.run("manage", "ops", "create", "name with spaces", "--password", "a b;$x")
    assert result.returncode == 0, result.stderr
    record = sandbox.records()[-1]
    assert record["tool"] == "uv"
    assert record["args"] == ["run", "python", "manager.py", "ops", "create", "name with spaces", "--password", "a b;$x"]
    assert record["cwd"] == str(sandbox.root / "apps/example-api-python")
    assert "unrelated-inspect" not in sandbox.actions()


def test_missing_host_manager_refuses(sandbox):
    result = sandbox.run("manage", "ops", "list")
    assert result.returncode != 0
    assert "manager.py missing" in result.stderr
    assert "uv" not in sandbox.actions()


def test_query_failure_does_not_fallback(sandbox):
    sandbox.host_manager()
    sandbox.env["FAIL_ACTION"] = "ps"
    assert sandbox.run("manage", "ops", "list").returncode != 0
    assert "uv" not in sandbox.actions()


@pytest.mark.parametrize("mode", ["host", "container", "unsupported"])
def test_explicit_runtime_modes(sandbox, mode):
    sandbox.host_manager()
    sandbox.mode(mode)
    result = sandbox.run("manage", "ops", "list")
    assert (result.returncode == 0) == (mode == "host")
    if mode == "host":
        assert set(sandbox.actions()) <= {"uv", "uv-version"}
        assert sandbox.actions()[-1] == "uv"
    else:
        assert "uv" not in sandbox.actions()


@pytest.mark.parametrize("container", [True, False])
def test_manager_failure_propagates(sandbox, container):
    sandbox.host_manager()
    sandbox.services(*(["api"] if container else []))
    sandbox.env["FAIL_ACTION"] = "manager" if container else "uv"
    assert sandbox.run("manage", "ops", "list").returncode == 37


@pytest.mark.parametrize("tty", [False, True])
@pytest.mark.parametrize("command", [("manage", "ops", "list"), ("db", "shell", "postgres"), ("db", "migrate", "status")])
def test_runtime_tty_policy(sandbox, tty, command):
    sandbox.services("api", "postgres")
    result = sandbox.run(*command, tty=tty)
    assert result.returncode == 0, result.stderr
    executions = [record for record in sandbox.records() if record["action"] in ("exec", "manager", "migration")]
    assert executions
    assert all(("-T" in record["args"]) == (not tty) for record in executions)


def test_migrations_remain_one_shots_and_preserve_revision_message(sandbox):
    result = sandbox.run("db", "migrate", "new", "message with spaces ; $literal")
    assert result.returncode == 0, result.stderr
    record = sandbox.records()[-1]
    assert record["action"] == "migration"
    assert record["args"][-4:] == ["alembic", "revision", "-m", "message with spaces ; $literal"]
    assert all(flag in record["args"] for flag in ("--rm", "--no-deps", "--build", "--user", "-T"))
    assert "uv" not in sandbox.actions()


@pytest.mark.parametrize("command,action", [(("db", "migrate", "status"), "migration"), (("db", "migrate", "new", "a b"), "migration"), (("db", "shell", "postgres"), "exec")])
def test_schema_and_shell_failures_propagate(sandbox, command, action):
    sandbox.env["FAIL_ACTION"] = action
    assert sandbox.run(*command).returncode == 37
    assert sandbox.actions().count(action) == 1


@pytest.mark.parametrize("command", [("db", "migrate"), ("db", "shell", "postgres")])
def test_unrelated_database_does_not_satisfy_runtime_guard(sandbox, command):
    sandbox.services()
    assert sandbox.run(*command).returncode != 0
    assert "migration" not in sandbox.actions()
    assert "exec" not in sandbox.actions()
    assert "unrelated-inspect" not in sandbox.actions()


@pytest.mark.parametrize("subcommand", ["up", "down", "status"])
def test_migration_failure_stops_following_one_shots(sandbox, subcommand):
    sandbox.env.update(DATA_SVCS="postgres neo4j", FAIL_ACTION="migration")
    directory = sandbox.root / "apps/database/neo4j"
    directory.mkdir(parents=True)
    (directory / "init.cypher").write_text("synthetic schema")
    assert sandbox.run("db", "migrate", subcommand).returncode == 37
    assert sandbox.actions().count("migration") == 1
    assert "neo4j-init" not in sandbox.actions()


def test_neo4j_init_failure_propagates(sandbox):
    sandbox.env.update(DATA_SVCS="postgres neo4j", FAIL_ACTION="neo4j-init")
    directory = sandbox.root / "apps/database/neo4j"
    directory.mkdir(parents=True)
    (directory / "init.cypher").write_text("synthetic schema")
    assert sandbox.run("db", "migrate", "up").returncode == 37
    assert sandbox.actions()[-2:] == ["migration", "neo4j-init"]


@pytest.mark.parametrize("engine", ["redis", "neo4j"])
def test_other_engine_shell_arguments(sandbox, engine):
    sandbox.services(engine)
    sandbox.env.update(REDIS_PASSWORD="synthetic redis pass", NEO4J_PASSWORD="synthetic neo4j pass")
    result = sandbox.run("db", "shell", engine)
    assert result.returncode == 0, result.stderr
    record = sandbox.records()[-1]
    assert "-T" in record["args"]
    assert f"synthetic {engine} pass" in record["args"]
