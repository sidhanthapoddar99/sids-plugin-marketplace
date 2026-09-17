import os
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest


TEMPLATE = Path(__file__).resolve().parents[2] / "template"
SERVER = '''
import http.server, os, signal, subprocess, sys, threading, time
from pathlib import Path
mode, port, directory = sys.argv[1:]
directory = Path(directory)
directory.mkdir(exist_ok=True)
(directory / "child").write_text(str(os.getpid()))
if mode == "early":
    sys.exit(23)
if mode == "descendants":
    child = subprocess.Popen([sys.executable, "-c", "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(90)"])
    (directory / "descendant").write_text(str(child.pid))
if mode == "timeout":
    time.sleep(90)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if mode != "unready" else 503)
        self.end_headers()
    def log_message(self, *args): pass
server = http.server.HTTPServer(("127.0.0.1", int(port)), Handler)
(directory / "listener").write_text(str(os.getpid()))
print("app output", flush=True)
if mode == "late":
    threading.Timer(1.5, lambda: os._exit(27)).start()
server.serve_forever()
'''


def eventually(predicate, seconds=6):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    assert predicate()


def alive(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1][0] != "Z"
    except FileNotFoundError:
        return False


@pytest.fixture
def project(tmp_path):
    root = tmp_path / "project space"
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    logs = tmp_path / "custom logs"
    (root / ".env").write_text(f"LOGS_DIR={logs}\nDATA_DIR=custom data\n")
    (root / ".env.template").write_text("LOGS_DIR=./logs\nDATA_DIR=./data\n")
    (root / "server.py").write_text(SERVER)
    library = root / "scripts/common/_lib.sh"
    with library.open("a") as stream:
        stream.write('''
source "$CTL_ROOT/scripts/common/_paths.sh"
source "$CTL_ROOT/scripts/common/_process.sh"
require_tools() { printf '%s\\n' "$@" >> "$CTL_ROOT/tools"; }
port_pid() { cat "$CTL_ROOT/port-$1/listener" 2>/dev/null || true; }
docker() { return 1; }
''')
    tracked = []

    def run(modes, detach=True, existing=False, probe_override=None, proxy=False):
        sockets = [socket.socket() for _ in modes]
        for handle in sockets:
            handle.bind(("127.0.0.1", 0))
        ports = [handle.getsockname()[1] for handle in sockets]
        for handle in sockets:
            handle.close()
        commands, probes = [], []
        for index, (mode, port) in enumerate(zip(modes, ports)):
            command = shlex.join([sys.executable, str(root / "server.py"), mode,
                                  str(port), str(root / f"port-{port}")])
            probe = shlex.join([sys.executable, "-c",
                f"import urllib.request; urllib.request.urlopen('http://127.0.0.1:{port}/ready', timeout=.3)"])
            probe = probe_override or probe
            if existing:
                server = subprocess.Popen(shlex.split(command), start_new_session=True,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                tracked.append(server)
                eventually(lambda: (root / f"port-{port}/listener").exists())
            commands.append(f"app{index}) printf '%s' {shlex.quote(command)} ;;")
            probes.append(f"app{index}) printf '%s' {shlex.quote(probe)} ;;")
        apps = root / "scripts/dev/_apps.sh"
        apps.write_text(
            "app_names() { printf '%s\\n' " + " ".join(f"app{index}" for index in range(len(modes))) + "; }\n"
            "frontends() { :; }\n"
            "app_tools() { echo fake-runtime; }\n"
            "app_port() { case $1 in " + " ".join(f"app{index}) echo {port} ;;" for index, port in enumerate(ports)) + " esac; }\n"
            "app_cmd() { case $1 in " + " ".join(commands) + " esac; }\n"
            "app_ready_cmd() { case $1 in " + " ".join(probes) + " esac; }\n"
            "app_ready_timeout() { echo 2; }\n"
        )
        process = subprocess.Popen(
            ["bash", str(root / "scripts/dev/dev.sh"), "--no-core", "--nqa",
             *(["--proxy"] if proxy else []),
             *(["--detach"] if detach else [])], cwd=tmp_path,
            env={"PATH": os.environ["PATH"], "CTL_ROOT": str(root), "NO_COLOR": "1", "DATA_SVCS": ""},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        tracked.append(process)
        return process, ports

    yield root, logs, run
    for process in tracked:
        if process.poll() is None:
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=8)
    subprocess.run(
        ["bash", "-c", 'source "$1"; for record in "$2"/run/*.process; do '
         '[[ -d $record ]] && process_stop "$record"; done', "bash",
         str(TEMPLATE / "scripts/common/_process.sh"), str(logs)], timeout=8,
        capture_output=True,
    )


def assert_children_stopped(root):
    for marker in [*root.glob("port-*/child"), *root.glob("port-*/descendant")]:
        eventually(lambda: not alive(int(marker.read_text())))


def test_detached_ready_and_storage(project):
    root, logs, run = project
    process, ports = run(["healthy"])
    stdout, stderr = process.communicate(timeout=8)
    assert process.returncode == 0, stderr
    assert "ready" in stdout
    assert alive(int((root / f"port-{ports[0]}/child").read_text()))
    assert (logs / "run/dev-app0.process/pid").exists()
    assert "app output" in (logs / "dev/dev-app0.log").read_text()
    assert not (root / "logs").exists()
    assert not (root / "data").exists()
    assert "mise" not in (root / "tools").read_text()
    assert "uv" not in (root / "tools").read_text()


@pytest.mark.parametrize("modes,expected", [(["early"], 23), (["unready"], 124),
    (["timeout"], 124), (["descendants", "early"], 23)])
def test_failed_launch_cleans_all(project, modes, expected):
    root, logs, run = project
    unrelated = subprocess.Popen(["sleep", "30"])
    try:
        process, _ = run(modes)
        process.communicate(timeout=9)
        assert process.returncode == expected
        assert_children_stopped(root)
        assert unrelated.poll() is None
        assert not list((logs / "run").glob("*.process"))
    finally:
        unrelated.terminate()
        unrelated.wait(timeout=3)


@pytest.mark.parametrize("sig", [signal.SIGINT, signal.SIGTERM])
@pytest.mark.parametrize("mode", ["descendants", "timeout"])
def test_interrupt_cleans_descendants(project, sig, mode):
    root, logs, run = project
    process, ports = run([mode], detach=False)
    eventually(lambda: (root / f"port-{ports[0]}/child").exists())
    if mode == "descendants":
        eventually(lambda: (logs / f"run/follow-dev-app0-{process.pid}.process/go").exists())
    process.send_signal(sig)
    stdout, stderr = process.communicate(timeout=8)
    assert process.returncode == 128 + sig, stderr
    assert_children_stopped(root)
    if mode == "descendants":
        assert "app output" in stdout


def test_unexpected_foreground_exit(project):
    root, _, run = project
    process, _ = run(["late"], detach=False)
    stdout, stderr = process.communicate(timeout=8)
    assert process.returncode == 27, (stdout, stderr)
    assert_children_stopped(root)


def test_pid_reuse_record_does_not_kill_other_process(tmp_path):
    unrelated = subprocess.Popen(["sleep", "30"], start_new_session=True)
    record = tmp_path / "stale.process"
    record.mkdir()
    (record / "pid").write_text(f"{unrelated.pid} 0\n")
    try:
        result = subprocess.run(["bash", "-c", 'source "$1"; process_stop "$2"',
            "bash", str(TEMPLATE / "scripts/common/_process.sh"), str(record)], timeout=4)
        assert result.returncode == 0
        assert unrelated.poll() is None
    finally:
        unrelated.terminate()
        unrelated.wait(timeout=3)


@pytest.mark.parametrize("mode,expected", [("healthy", 0), ("unready", 124)])
def test_existing_listener_requires_readiness_and_survives(project, mode, expected):
    root, logs, run = project
    process, ports = run([mode], existing=True)
    stdout, stderr = process.communicate(timeout=7)
    assert process.returncode == expected, (stdout, stderr)
    assert alive(int((root / f"port-{ports[0]}/child").read_text()))
    assert not list(logs.glob("run/*.process"))


def test_hanging_probe_is_bounded(project):
    root, _, run = project
    process, _ = run(["healthy"], probe_override="sleep 90")
    process.communicate(timeout=7)
    assert process.returncode == 124
    assert_children_stopped(root)


def test_detached_crash_can_restart(project):
    root, logs, run = project
    process, _ = run(["late"])
    process.communicate(timeout=7)
    assert process.returncode == 0
    record = logs / "run/dev-app0.process"
    eventually(lambda: (record / "status").exists())
    eventually(lambda: not alive(int((record / "pid").read_text().split()[0])))
    process, _ = run(["healthy"])
    stdout, stderr = process.communicate(timeout=7)
    assert process.returncode == 0, (stdout, stderr)
    assert not (record / "status").exists()


def test_live_record_is_preserved(project):
    root, logs, run = project
    first, _ = run(["healthy"])
    first.communicate(timeout=7)
    assert first.returncode == 0
    record = logs / "run/dev-app0.process/pid"
    identity = record.read_text()
    second, _ = run(["healthy"])
    second.communicate(timeout=7)
    assert second.returncode != 0
    assert record.read_text() == identity
    assert alive(int(identity.split()[0]))


@pytest.mark.parametrize("preexisting", [False, True])
@pytest.mark.parametrize("interrupt", [False, True])
def test_proxy_cleanup_preserves_existing(project, preexisting, interrupt):
    root, _, run = project
    binary = root / "fake-bin"
    binary.mkdir()
    docker = binary / "docker"
    docker.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$CTL_ROOT/docker-calls"\n')
    docker.chmod(0o755)
    curl = binary / "curl"
    curl.write_text('#!/usr/bin/env bash\nexit 0\n')
    curl.chmod(0o755)
    if preexisting:
        (root / "proxy-running").touch()
    with (root / "scripts/common/_lib.sh").open("a") as stream:
        stream.write('''
export PATH="$CTL_ROOT/fake-bin:$PATH"
DEV_PROXY_PORT=12345
require_docker() { :; }
dc_dev() {
  case "$1" in
    ps) [[ ! -f $CTL_ROOT/proxy-running ]] || echo isolated-proxy ;;
    up) touch "$CTL_ROOT/proxy-running" "$CTL_ROOT/proxy-started" ;;
  esac
  return 0
}
''')
    process, ports = run(["timeout" if interrupt else "early"], proxy=True)
    if interrupt:
        eventually(lambda: (root / f"port-{ports[0]}/child").exists())
        process.send_signal(signal.SIGTERM)
    stdout, stderr = process.communicate(timeout=8)
    assert process.returncode == (143 if interrupt else 23), (stdout, stderr)
    calls = root / "docker-calls"
    assert calls.exists() != preexisting
    assert (root / "proxy-started").exists() != preexisting
    if calls.exists():
        assert calls.read_text() == "stop isolated-proxy\n"


def test_ps_stops_owned_descendants_from_custom_logs(project):
    root, _, run = project
    process, ports = run(["descendants"])
    process.communicate(timeout=7)
    assert process.returncode == 0
    result = subprocess.run(
        ["bash", str(root / "scripts/dev/ps.sh"), "kill", str(ports[0]), "-y"],
        env={"PATH": os.environ["PATH"], "CTL_ROOT": str(root),
             "API_PORT": str(ports[0]), "NO_COLOR": "1"},
        cwd=root.parent, capture_output=True, text=True, timeout=6,
    )
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert_children_stopped(root)


@pytest.mark.parametrize("sig", [signal.SIGINT, signal.SIGTERM])
def test_interrupt_before_pid_capture(project, sig):
    root, logs, run = project
    binary = root / "fake-bin"
    binary.mkdir()
    launcher = binary / "setsid"
    launcher.write_text('#!/usr/bin/env bash\ntouch "$CTL_ROOT/launching"\nsleep .3\nexec '
                        + shlex.quote(shutil.which("setsid")) + ' "$@"\n')
    launcher.chmod(0o755)
    with (root / "scripts/common/_lib.sh").open("a") as stream:
        stream.write('\nexport PATH="$CTL_ROOT/fake-bin:$PATH"\n')
    process, _ = run(["healthy"])
    eventually(lambda: (root / "launching").exists())
    process.send_signal(sig)
    process.communicate(timeout=7)
    assert process.returncode == 128 + sig
    assert not list(logs.glob("run/*.process"))
    assert not list(root.glob("port-*/child"))


@pytest.mark.parametrize("hang,preexisting", [(True, False), (False, False), (False, True)])
def test_proxy_start_and_readiness_are_bounded(project, hang, preexisting):
    root, _, run = project
    binary = root / "fake-bin"
    binary.mkdir()
    for name, body in {
        "curl": "exit 1",
        "docker": 'printf "%s\\n" "$*" >> "$CTL_ROOT/docker-calls"',
    }.items():
        executable = binary / name
        executable.write_text("#!/usr/bin/env bash\n" + body + "\n")
        executable.chmod(0o755)
    if preexisting:
        (root / "proxy-running").touch()
    with (root / "scripts/common/_lib.sh").open("a") as stream:
        stream.write('''
export PATH="$CTL_ROOT/fake-bin:$PATH"
DEV_PROXY_PORT=12345
require_docker() { :; }
dc_dev() {
  case "$1" in
    ps) [[ ! -f $CTL_ROOT/proxy-running ]] || echo isolated-proxy ;;
    up) touch "$CTL_ROOT/proxy-running"; ''' + ("sleep 90" if hang else ":") + ''' ;;
  esac
  return 0
}
''')
    worker = root / "scripts/dev/dev.sh"
    worker.write_text(worker.read_text().replace("proxy_command 60 up", "proxy_command 1 up")
                      .replace('process_ready 30 "$proxy_probe"', 'process_ready 1 "$proxy_probe"'))
    process, _ = run(["healthy"], proxy=True)
    stdout, stderr = process.communicate(timeout=7)
    assert process.returncode == 124, (stdout, stderr)
    assert not list(root.glob("port-*/child"))
    assert (root / "docker-calls").exists() != preexisting
