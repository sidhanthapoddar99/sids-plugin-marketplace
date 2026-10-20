"""ctl dev and the data core: reuse, the ask, migrations, and the stops that keep or end the core.

The tests run the real template ctl in a scratch project. A recording Docker shim stands in for the
daemon: it keeps the containers of one Compose project in a state file, so a test can begin with
the core running or stopped and read every Docker call afterwards. No container starts. The prompt
tests run ctl inside a pseudo-terminal, so `[[ -t 1 && -r /dev/tty ]]` holds as it does for a person.
"""

import json
import os
import pty
import select
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
ENGINES = ["postgres", "redis", "neo4j"]
IDS = {"postgres": "d1", "redis": "d2", "neo4j": "d3", "api": "a1", "migrate": "b1", "neo4j-init": "b2"}

SHIM = r'''
import json, os, sys
from pathlib import Path

root = Path(os.environ["TEST_ROOT"])
args = sys.argv[1:]
with (root / "docker.calls").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
state_file = root / "docker.state"
state = json.loads(state_file.read_text())
containers = state["containers"]
by_id = {container["id"]: container for container in containers.values()}
ids = json.loads(os.environ["SHIM_IDS"])
check = {"test": ["CMD-SHELL", "ready"]}
model = {"name": "fixture-project", "services": {
    "postgres": {"healthcheck": check}, "redis": {"healthcheck": check}, "neo4j": {"healthcheck": check},
    "migrate": {"build": {"context": "."}, "depends_on": {"postgres": {"condition": "service_healthy"}}},
    "neo4j-init": {"depends_on": {"neo4j": {"condition": "service_healthy"}}},
    "api": {"build": {"context": "."}, "healthcheck": check,
            "depends_on": {"postgres": {"condition": "service_healthy"},
                           "migrate": {"condition": "service_completed_successfully"}}},
}}


def save():
    state_file.write_text(json.dumps(state))


if args[0] == "info":
    sys.exit(0)
if args[0] == "compose":
    rest, files, index = args[1:], [], 0
    while index < len(rest) and rest[index] in ("--project-directory", "--env-file", "-f"):
        if rest[index] == "-f":
            files.append(rest[index + 1])
        index += 2
    command, options = (rest[index], rest[index + 1:]) if index < len(rest) else ("", [])
    if command == "version":
        print("Docker Compose version v2.99.0")
    elif command == "config":
        if "--services" in options:
            print("\n".join(model["services"]))
        elif "--format" in options:
            print(json.dumps(model))
    elif command == "build" and "--help" in options:
        print("--with-dependencies")
    elif command == "up":
        exposed = any(name.endswith("compose.m.expose_db.yaml") for name in files)
        for service in [option for option in options if not option.startswith("-")]:
            container = containers.setdefault(service, {"id": ids[service]})
            container.update(state="running", health="healthy",
                             ports=["5432"] if exposed and service in ("postgres", "redis", "neo4j") else [])
        save()
    elif command == "ps":
        if "--services" in options:
            print("\n".join(name for name, item in containers.items() if item["state"] == "running"))
        else:
            every = "--all" in options or any(option.startswith("-") and "a" in option[1:] and not option.startswith("--") for option in options)
            container = containers.get(options[-1])
            if container and (every or container["state"] == "running"):
                print(container["id"])
    elif command == "run":
        sys.exit(state.get("run_exit", 0))
    sys.exit(0)
if args[0] == "ps":
    for name, container in containers.items():
        print(container["id"], name, container["state"])
    sys.exit(0)
if args[0] == "inspect":
    flag = "--format" if "--format" in args else "-f"
    form = args[args.index(flag) + 1]
    for identifier in args[args.index(flag) + 2:]:
        container = by_id[identifier]
        running = container["state"] == "running"
        if "json .State" in form:
            body = {"Status": container["state"], "ExitCode": 0}
            if running and container.get("health"):
                body["Health"] = {"Status": container["health"]}
            print(json.dumps(body))
        elif "Health" in form:
            print(container["health"] if running and container.get("health") else container["state"])
        elif "Ports" in form:
            print(" ".join(container.get("ports", [])))
        elif "State.Running" in form:
            print("true false false" if running else "false false false")
    sys.exit(0)
if args[0] == "stop":
    for identifier in args[3:]:
        by_id[identifier]["state"] = "exited"
    save()
    sys.exit(0)
sys.exit(99)
'''

SERVER = r'''
import http.server, os, sys
from pathlib import Path
port, marker = int(sys.argv[1]), Path(sys.argv[2])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", port), Handler)
marker.write_text(str(os.getpid()))
print("app output", flush=True)
server.serve_forever()
'''


def free_port() -> int:
    with socket.socket() as handle:
        handle.bind(("127.0.0.1", 0))
        return handle.getsockname()[1]


def alive(pid: int) -> bool:
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1][0] != "Z"
    except FileNotFoundError:
        return False


def eventually(predicate, seconds: float = 6) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    assert predicate()


class Project:
    def __init__(self, root: Path, home: Path):
        self.root = root
        port = free_port()
        settings = (f"LOGS_DIR=./logs\nDATA_DIR=./data\nCOMPOSE_PROJECT_NAME=fixture-project\n"
                    f"POSTGRES_PORT=15432\nREDIS_PORT=16379\nNEO4J_BOLT_PORT=17687\nAPP_PORT={port}\n")
        (root / ".env").write_text(settings)
        (root / ".env.template").write_text(settings)
        (root / "server.py").write_text(SERVER)
        (root / "apps/database/neo4j").mkdir(parents=True)
        (root / "apps/database/neo4j/init.cypher").write_text("RETURN 1;\n")
        (root / "scripts/dev/_apps.sh").write_text(
            "app_names() { echo app0; }\n"
            "rust_app_names() { :; }\n"
            "app_tools() { :; }\n"
            "app_port() { echo \"$APP_PORT\"; }\n"
            "app_cmd() { printf '%q %q %q %q' \"$FIXTURE_PYTHON\" \"$CTL_ROOT/server.py\" \"$APP_PORT\" \"$CTL_ROOT/app.pid\"; }\n"
            "app_ready_cmd() { printf '%q -c %q' \"$FIXTURE_PYTHON\" "
            "\"import urllib.request; urllib.request.urlopen('http://127.0.0.1:$APP_PORT/', timeout=.3)\"; }\n"
            "app_ready_timeout() { echo 5; }\n"
        )
        binaries = root.parent / "bin"
        binaries.mkdir()
        (binaries / "docker").write_text(f"#!{sys.executable}\n" + SHIM)
        (binaries / "docker").chmod(0o755)
        self.env = {
            "PATH": f"{binaries}{os.pathsep}{os.environ['PATH']}", "HOME": str(home),
            "TEST_ROOT": str(root), "SHIM_IDS": json.dumps(IDS), "NO_COLOR": "1", "TERM": "dumb",
            "PROCESS_STOP_TIMEOUT": "2", "FIXTURE_PYTHON": sys.executable,
        }
        self.core("stopped")

    # ── the shim's state ──
    def core(self, mode: str, *, ports: bool = True, extra: dict | None = None, run_exit: int = 0) -> None:
        containers = {}
        if mode == "running":
            for name in ENGINES:
                containers[name] = {"id": IDS[name], "state": "running", "health": "healthy",
                                    "ports": ["15432"] if ports else []}
        elif mode == "exited":
            for name in ENGINES:
                containers[name] = {"id": IDS[name], "state": "exited", "ports": []}
        containers.update(extra or {})
        (self.root / "docker.state").write_text(json.dumps({"containers": containers, "run_exit": run_exit}))
        (self.root / "docker.calls").unlink(missing_ok=True)

    def state(self) -> dict:
        return json.loads((self.root / "docker.state").read_text())["containers"]

    def calls(self) -> list[list[str]]:
        path = self.root / "docker.calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def compose(self, command: str) -> list[list[str]]:
        found = []
        for call in self.calls():
            if call[:1] != ["compose"]:
                continue
            index = 1
            while index < len(call) and call[index] in ("--project-directory", "--env-file", "-f"):
                index += 2
            if index < len(call) and call[index] == command and "--help" not in call:
                found.append(call)
        return found

    def stopped_ids(self) -> list[str]:
        return [call[-1] for call in self.calls() if call[0] == "stop"]

    def migrated(self) -> bool:
        runs = self.compose("run")
        return (any(call[-2:] == ["migrate", "migrate"] and "--no-deps" in call for call in runs)
                and any(call[-1] == "neo4j-init" and "--no-deps" in call for call in runs))

    # ── running ctl ──
    def ctl(self, *arguments: str, timeout: float = 30) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", str(self.root / "ctl"), *arguments], env=self.env, cwd=self.root.parent,
                              text=True, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)

    def ctl_in_terminal(self, *arguments: str, answer: bytes | None = None, timeout: float = 30) -> tuple[int, str]:
        """Run ctl with a pseudo-terminal as its controlling terminal; type `answer` at the first prompt."""
        bash = shutil.which("bash")
        argv = ["bash", str(self.root / "ctl"), *arguments]
        pid, descriptor = pty.fork()
        if pid == 0:
            os.chdir(self.root.parent)
            os.execve(bash, argv, self.env)
        output, answered, deadline = b"", False, time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([descriptor], [], [], 0.1)
                if not ready:
                    continue
                try:
                    chunk = os.read(descriptor, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if answer is not None and not answered and (b"[Y/n]" in output or b"[y/N]" in output):
                    os.write(descriptor, answer)
                    answered = True
            else:
                os.kill(pid, signal.SIGKILL)
        finally:
            _, status = os.waitpid(pid, 0)
            os.close(descriptor)
        return os.waitstatus_to_exitcode(status), output.decode(errors="replace")

    def app_pid(self) -> int:
        return int((self.root / "app.pid").read_text())

    def record(self) -> Path:
        return self.root / "logs/run/dev-app0.process"


@pytest.fixture
def project(tmp_path: Path):
    root = tmp_path / "project space"
    root.mkdir()
    for name in ("ctl", "scripts", "docker"):
        source = TEMPLATE / name
        (shutil.copytree if source.is_dir() else shutil.copy2)(source, root / name)
    home = tmp_path / "home"
    home.mkdir()
    fixture = Project(root, home)
    yield fixture
    subprocess.run(
        ["bash", "-c", 'source "$1"; for record in "$2"/run/*.process; do '
         '[[ -d $record ]] && process_stop "$record"; done', "bash",
         str(TEMPLATE / "scripts/common/_process.sh"), str(root / "logs")], timeout=10, capture_output=True,
    )


def assert_core_untouched(project: Project) -> None:
    assert not project.compose("up"), "a running core must not be started again"
    assert not project.stopped_ids()
    for command in ("restart", "down", "rm", "stop", "kill"):
        assert not project.compose(command)
    assert all(project.state()[name]["state"] == "running" for name in ENGINES)


# ── 1. a running core is reused, never restarted, and still migrated ──

@pytest.mark.parametrize("terminal", [False, True])
def test_running_core_is_reused_not_restarted_and_migrated(project: Project, terminal: bool) -> None:
    project.core("running")
    if terminal:
        code, output = project.ctl_in_terminal("dev", "app0", "--detach")
        assert "[Y/n]" not in output
    else:
        result = project.ctl("dev", "app0", "--detach")
        code, output = result.returncode, result.stdout + result.stderr
    assert code == 0, output
    assert "reused, not restarted" in output
    assert_core_untouched(project)
    assert all(call[-1] == "migrate" for call in project.compose("build"))
    assert project.migrated()
    assert alive(project.app_pid())


def test_migration_failure_stops_the_launch(project: Project) -> None:
    project.core("running", run_exit=5)
    result = project.ctl("dev", "app0", "--detach")
    assert result.returncode != 0
    assert "migrations failed" in result.stderr
    assert not (project.root / "app.pid").exists()
    assert_core_untouched(project)


def test_core_without_loopback_ports_is_refused_not_restarted(project: Project) -> None:
    project.core("running", ports=False)
    result = project.ctl("dev", "app0", "--detach")
    assert result.returncode != 0
    assert "without loopback ports" in result.stderr and "ctl stop" in result.stderr
    assert_core_untouched(project)
    assert not project.compose("run")
    assert not (project.root / "app.pid").exists()


# ── 2. a stopped core: the ask in a terminal, and its no-question forms ──

def started_without_build(project: Project) -> bool:
    ups = project.compose("up")
    # the only image ctl dev builds is the migration image, which carries this checkout's SQL
    return (len(ups) == 1 and ups[0][-5:] == ["-d", "--no-build", *ENGINES]
            and "docker/compose.m.expose_db.yaml" in ups[0]
            and all(call[-1] == "migrate" for call in project.compose("build")))


@pytest.mark.parametrize("state", ["stopped", "exited"])
def test_enter_at_the_ask_starts_the_core(project: Project, state: str) -> None:
    project.core(state)
    code, output = project.ctl_in_terminal("dev", "app0", "--detach", answer=b"\n")
    assert code == 0, output
    assert "The database is not running. Start it with 'ctl dev db --detach' [Y/n]" in output
    assert started_without_build(project)
    assert project.migrated()
    assert alive(project.app_pid())


def test_no_at_the_ask_starts_nothing(project: Project) -> None:
    code, output = project.ctl_in_terminal("dev", "app0", "--detach", answer=b"n\n")
    assert code != 0
    assert "start it with: ctl dev db --detach" in output
    assert not project.compose("up")
    assert not project.compose("run")
    assert not (project.root / "app.pid").exists()


@pytest.mark.parametrize("form", ["no terminal", "--all", "--nqa"])
def test_core_starts_without_asking(project: Project, form: str) -> None:
    if form == "no terminal":
        result = project.ctl("dev", "app0", "--detach")
        code, output = result.returncode, result.stdout + result.stderr
    else:
        code, output = project.ctl_in_terminal("dev", "app0", "--detach", form, answer=b"n\n")
    assert code == 0, output
    assert "[Y/n]" not in output
    assert started_without_build(project)
    assert project.migrated()


# ── 3. stopping the apps leaves the core running ──

@pytest.mark.parametrize("form", ["no terminal", "--nqa", "enter"])
def test_dev_stop_keeps_the_core(project: Project, form: str) -> None:
    project.core("running")
    assert project.ctl("dev", "app0", "--detach").returncode == 0
    pid = project.app_pid()
    project.core("running")
    if form == "no terminal":
        result = project.ctl("dev", "stop")
        code, output = result.returncode, result.stdout + result.stderr
    elif form == "--nqa":
        code, output = project.ctl_in_terminal("dev", "stop", "--nqa", answer=b"y\n")
        assert "[y/N]" not in output
    else:
        code, output = project.ctl_in_terminal("dev", "stop", answer=b"\n")
        assert "Also stop the database (ctl dev db stop) [y/N]" in output
    assert code == 0, output
    eventually(lambda: not alive(pid))
    assert not project.record().exists()
    assert_core_untouched(project)


def test_yes_at_the_dev_stop_ask_stops_the_core_too(project: Project) -> None:
    project.core("running")
    assert project.ctl("dev", "app0", "--detach").returncode == 0
    pid = project.app_pid()
    project.core("running")
    code, output = project.ctl_in_terminal("dev", "stop", answer=b"y\n")
    assert code == 0, output
    eventually(lambda: not alive(pid))
    assert project.stopped_ids() == [IDS[name] for name in ENGINES]


def test_interrupting_a_foreground_launch_leaves_the_core_running(project: Project) -> None:
    project.core("running")
    process = subprocess.Popen(["bash", str(project.root / "ctl"), "dev", "app0"], env=project.env,
                               cwd=project.root.parent, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        eventually(lambda: (project.root / "app.pid").exists(), seconds=20)
        pid = project.app_pid()
        eventually(lambda: project.record().exists())
        time.sleep(0.5)
        calls_before = len(project.calls())
        os.killpg(process.pid, signal.SIGINT)
        process.communicate(timeout=10)
        assert process.returncode == 130
        eventually(lambda: not alive(pid))
        assert len(project.calls()) == calls_before, "cleanup must not call Docker"
        assert_core_untouched(project)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()


# ── 4. --all stops both, apps first ──

def test_dev_stop_all_stops_the_apps_then_the_core(project: Project) -> None:
    project.core("running")
    assert project.ctl("dev", "app0", "--detach").returncode == 0
    pid = project.app_pid()
    project.core("running", extra={"api": {"id": IDS["api"], "state": "running", "health": "healthy"}})
    result = project.ctl("dev", "stop", "--all")
    assert result.returncode == 0, result.stderr
    eventually(lambda: not alive(pid))
    assert not project.record().exists()
    assert project.stopped_ids() == [IDS["api"], *[IDS[name] for name in ENGINES]]
    assert all(container["state"] == "exited" for container in project.state().values())
    assert "project stopped" in result.stdout


def test_ctl_stop_still_stops_everything(project: Project) -> None:
    project.core("running", extra={"api": {"id": IDS["api"], "state": "running", "health": "healthy"}})
    assert project.ctl("dev", "app0", "--detach").returncode == 0
    pid = project.app_pid()
    result = project.ctl("stop")
    assert result.returncode == 0, result.stderr
    eventually(lambda: not alive(pid))
    assert project.stopped_ids() == [IDS["api"], *[IDS[name] for name in ENGINES]]


# ── ctl dev db ──

def test_dev_db_starts_the_core_detached_without_a_build(project: Project) -> None:
    result = project.ctl("dev", "db", "--detach")
    assert result.returncode == 0, result.stderr
    assert started_without_build(project)
    assert project.migrated()
    assert "stop it with ctl dev db stop" in result.stdout


def test_dev_db_on_a_running_core_only_migrates(project: Project) -> None:
    project.core("running")
    result = project.ctl("dev", "db")
    assert result.returncode == 0, result.stderr
    assert_core_untouched(project)
    assert project.migrated()


def test_dev_db_stop_stops_only_the_engines(project: Project) -> None:
    project.core("running", extra={"migrate": {"id": IDS["migrate"], "state": "exited"}})
    result = project.ctl("dev", "db", "stop")
    assert result.returncode == 0, result.stderr
    assert project.stopped_ids() == [IDS[name] for name in ENGINES]


def test_dev_db_stop_refuses_while_a_dev_app_runs(project: Project) -> None:
    project.core("running")
    assert project.ctl("dev", "app0", "--detach").returncode == 0
    project.core("running")
    result = project.ctl("dev", "db", "stop")
    assert result.returncode != 0
    assert "ctl dev stop --all" in result.stderr
    assert alive(project.app_pid())
    assert_core_untouched(project)


def test_dev_db_stop_refuses_while_an_app_container_runs(project: Project) -> None:
    project.core("running", extra={"api": {"id": IDS["api"], "state": "running", "health": "healthy"}})
    result = project.ctl("dev", "db", "stop")
    assert result.returncode != 0
    assert "app containers still run on the data core: api" in result.stderr
    assert not project.stopped_ids()


# ── help and dry runs ──

def test_help_names_the_data_core_commands(project: Project) -> None:
    overview = project.ctl("--help")
    assert overview.returncode == 0
    assert "dev db [--detach] | dev db stop" in overview.stdout and "dev stop [--all]" in overview.stdout
    for arguments in (["dev", "--help"], ["dev", "db", "--help"], ["dev", "db", "stop", "--help"], ["dev", "stop", "--help"]):
        result = project.ctl(*arguments)
        assert result.returncode == 0, (arguments, result.stderr)
        assert "data core" in result.stdout
    assert not project.calls()


@pytest.mark.parametrize("arguments", [["dev", "app0", "--dry-run"], ["dev", "db", "--dry-run"],
                                       ["dev", "db", "stop", "--dry-run"], ["dev", "stop", "--dry-run"]])
def test_dry_runs_change_nothing(project: Project, arguments: list[str]) -> None:
    project.core("running")
    result = project.ctl(*arguments)
    assert result.returncode == 0, result.stderr
    assert_core_untouched(project)
    assert not project.compose("run")
    assert not project.compose("build")
