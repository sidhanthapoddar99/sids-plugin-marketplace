import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest


TEMPLATE = Path(__file__).resolve().parents[2] / "template"


def alive(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1][0] != "Z"
    except FileNotFoundError:
        return False


def eventually(predicate):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    assert predicate()


@pytest.fixture
def project(tmp_path):
    root = tmp_path / "project space"
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    shutil.copy2(TEMPLATE / "ctl", root / "ctl")
    logs = root / "custom logs"
    (root / ".env").write_text("LOGS_DIR=custom logs\nCOMPOSE_PROJECT_NAME=chosen-project\n")
    binaries = root / "bin"
    binaries.mkdir()
    docker = binaries / "docker"
    docker.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
root = Path(os.environ["TEST_ROOT"])
args = sys.argv[1:]
with (root / "docker.calls").open("a") as stream:
    stream.write(json.dumps(args) + "\\n")
mode = os.environ.get("DOCKER_FAILURE", "")
if args[0] == "info":
    sys.exit(1 if mode == "info" else 0)
if args[0] == "compose":
    assert args[1:3] == ["--project-directory", str(root)]
    assert args[-3:] == ["config", "--format", "json"]
    print('{"name":"chosen-project"}')
    sys.exit(1 if mode == "config" else 0)
if args[0] == "ps":
    assert "label=com.docker.compose.project=chosen-project" in args
    assert "label=com.docker.compose.project.working_dir=" + str(root) in args
    print("a1 api\\na2 dev-proxy\\nd1 postgres")
    sys.exit(1 if mode == "list" else 0)
if args[0] == "stop":
    assert args[1:3] == ["--time", "10"]
    for marker in root.glob("*.child"):
        stat = Path("/proc/" + marker.read_text() + "/stat")
        assert not stat.exists() or stat.read_text().rsplit(") ", 1)[1][0] == "Z"
    sys.exit(1 if mode == "stop" or mode == args[-1] else 0)
if args[0] == "inspect":
    print("true false false" if mode == "running" else "false false false")
    sys.exit(1 if mode == "inspect" else 0)
sys.exit(99)
''')
    docker.chmod(0o755)
    env = {"PATH": f"{binaries}:{os.environ['PATH']}", "TEST_ROOT": str(root),
           "CTL_ROOT": str(root), "NO_COLOR": "1", "PROCESS_STOP_TIMEOUT": "1"}
    leaders = []

    def start(name, detached=True, graceful=False):
        command = '''
import os, signal, subprocess, sys, time
from pathlib import Path
root, name = Path(sys.argv[1]), sys.argv[2]
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, "-c", "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(90)"])
def cleanup(signum, frame):
    time.sleep(0.6)
    child.kill()
    child.wait()
    (root / (name + ".cleaned")).write_text("complete")
    sys.exit(0)
if sys.argv[3] == "graceful":
    signal.signal(signal.SIGTERM, cleanup)
(root / (name + ".child")).write_text(str(child.pid))
(root / (name + ".watcher")).write_text(str(os.getpid()))
time.sleep(90)
'''
        launcher = subprocess.Popen(
            ["bash", "-euc", 'source "$1"; load_env_files; expand_env_refs; process_init; process_start "$2" "$CTL_ROOT" '
             '"$3" -c "$4" "$CTL_ROOT" "$2" "$5"; '
             + ("process_release" if detached else "process_monitor"), "bash",
             str(root / "scripts/common/_lib.sh"), name, sys.executable, command,
             "graceful" if graceful else "stubborn"],
            env=env, cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        record = logs / f"run/{name}.process"
        eventually(lambda: (record / "pid").exists() and (root / f"{name}.child").exists())
        leaders.append(int((record / "pid").read_text().split()[0]))
        if detached:
            assert launcher.wait(timeout=5) == 0
        return record, launcher

    def stop(*arguments, failure=""):
        return subprocess.run(["bash", str(root / "ctl"), "stop", *arguments],
                              env={**env, "DOCKER_FAILURE": failure}, cwd=tmp_path,
                              text=True, capture_output=True, timeout=15)

    yield root, logs, env, start, stop
    for leader in leaders:
        try:
            os.killpg(leader, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.mark.parametrize("detached", [True, False])
def test_stop_descendants_frozen_groups_and_repeat(project, detached):
    root, logs, env, start, stop = project
    record, launcher = start("api", detached)
    frozen, _ = start("build-5290")
    unrelated = subprocess.Popen(["sleep", "90"], start_new_session=True)
    try:
        result = stop()
        assert result.returncode == 0, result.stderr
        for marker in [*root.glob("*.child"), *root.glob("*.watcher")]:
            assert not alive(int(marker.read_text()))
        assert unrelated.poll() is None
        assert not record.exists() and not frozen.exists()
        assert stop().returncode == 0
        calls = [json.loads(line) for line in (root / "docker.calls").read_text().splitlines()]
        assert [call[-1] for call in calls if call[0] == "stop"] == ["a1", "a2", "d1"] * 2
        assert all(call[0] not in {"rm", "down", "volume"} for call in calls)
        if not detached:
            launcher.wait(timeout=5)
    finally:
        unrelated.terminate()
        unrelated.wait(timeout=5)


def test_stale_recycled_pid_and_incomplete_records(project):
    root, logs, env, start, stop = project
    unrelated = subprocess.Popen(["sleep", "90"], start_new_session=True)
    try:
        birth = Path(f"/proc/{unrelated.pid}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        for name, contents in [("stale", "99999999 1"), ("reused", f"{unrelated.pid} {int(birth) + 1}"), ("incomplete", None)]:
            record = logs / f"run/{name}.process"
            record.mkdir(parents=True)
            if contents:
                (record / "pid").write_text(contents + "\n")
        result = stop()
        assert result.returncode == 0, result.stderr
        assert not list((logs / "run").glob("*.process"))
        assert unrelated.poll() is None
    finally:
        unrelated.terminate()
        unrelated.wait(timeout=5)


@pytest.mark.parametrize("failure", ["info", "config", "list", "stop", "inspect", "running", "d1"])
def test_docker_failures_do_not_prevent_host_cleanup(project, failure):
    root, logs, env, start, stop = project
    record, _ = start("watcher")
    result = stop(failure=failure)
    assert result.returncode != 0
    assert not record.exists()
    assert not alive(int((root / "watcher.child").read_text()))
    if failure in {"stop", "inspect", "running"}:
        calls = [json.loads(line) for line in (root / "docker.calls").read_text().splitlines()]
        assert not any(call[0] == "stop" and call[-1] == "d1" for call in calls)


def test_missing_docker_after_host_cleanup(project):
    root, logs, env, start, stop = project
    record, _ = start("api")
    with (root / "scripts/common/_lib.sh").open("a") as stream:
        stream.write('\ncommand() { if [[ $* == "-v docker" ]]; then return 1; fi; builtin command "$@"; }\n')
    result = stop()
    assert result.returncode != 0
    assert "not installed" in result.stderr
    assert not record.exists()


def test_dry_run_leaves_everything_untouched(project):
    root, logs, env, start, stop = project
    record, _ = start("api")
    result = stop("--dry-run")
    assert result.returncode == 0, result.stderr
    assert record.exists()
    assert alive(int((root / "api.child").read_text()))
    calls = [json.loads(line) for line in (root / "docker.calls").read_text().splitlines()]
    assert not any(call[0] == "stop" for call in calls)


@pytest.mark.parametrize("mode", ["foreign", "signal-failure", "symlink"])
def test_unsafe_or_failed_host_shutdown_preserves_databases(project, mode):
    root, logs, env, start, stop = project
    record, _ = start("api")
    if mode == "foreign":
        (record / "project").write_text("/another/project\n")
    elif mode == "signal-failure":
        with (root / "scripts/common/_lib.sh").open("a") as stream:
            stream.write('\nkill() { return 1; }\n')
    else:
        record.rename(record.with_suffix(".hidden"))
        record.symlink_to(record.with_suffix(".hidden"), target_is_directory=True)
    result = stop()
    assert result.returncode != 0
    assert record.exists()
    assert alive(int((root / "api.child").read_text()))
    assert not (root / "docker.calls").exists()


def test_help_and_invalid_arguments(project):
    root, logs, env, start, stop = project
    assert stop("--help").returncode == 0
    assert stop("unexpected").returncode != 0
    assert not (root / "docker.calls").exists()


def test_term_allows_watcher_cleanup_before_group_kill(project):
    root, logs, env, start, stop = project
    env["PROCESS_STOP_TIMEOUT"] = "3"
    record, _ = start("watcher", graceful=True)
    result = stop()
    assert result.returncode == 0, result.stderr
    assert (root / "watcher.cleaned").read_text() == "complete"
    assert not record.exists()


def test_old_foreground_cleanup_cannot_kill_replacement(project):
    root, logs, env, start, stop = project
    record, launcher = start("api", detached=False)
    launcher.send_signal(signal.SIGSTOP)
    try:
        result = stop()
        assert result.returncode == 0, result.stderr
        (root / "api.child").unlink()
        replacement, _ = start("api")
        launcher.send_signal(signal.SIGCONT)
        launcher.wait(timeout=5)
        assert replacement.exists()
        assert alive(int((root / "api.child").read_text()))
    finally:
        if launcher.poll() is None:
            launcher.send_signal(signal.SIGCONT)
            launcher.terminate()
            launcher.wait(timeout=5)


def test_live_pid_only_is_refused(project):
    root, logs, env, start, stop = project
    record, _ = start("api")
    pid = (record / "pid").read_text().split()[0]
    (record / "pid").write_text(pid + "\n")
    result = stop()
    assert result.returncode != 0
    assert "without a start identity" in result.stderr
    assert record.exists()
    assert alive(int((root / "api.child").read_text()))


def test_legacy_identity_record_inside_project_is_supported(project):
    root, logs, env, start, stop = project
    record, _ = start("api")
    (record / "project").unlink()
    result = stop()
    assert result.returncode == 0, result.stderr
    assert not record.exists()


def test_zombie_record_is_not_a_live_group(project):
    root, logs, env, start, stop = project
    process = subprocess.Popen(["sleep", "0.1"], start_new_session=True)
    try:
        birth = Path(f"/proc/{process.pid}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        record = logs / "run/zombie.process"
        record.mkdir(parents=True)
        (record / "pid").write_text(f"{process.pid} {birth}\n")
        eventually(lambda: not alive(process.pid))
        result = subprocess.run(["bash", "-c", 'source "$1"; process_valid "$2"', "bash",
                                 str(root / "scripts/common/_process.sh"), str(record)], env=env)
        assert result.returncode != 0
        assert stop().returncode == 0
        assert not record.exists()
    finally:
        process.wait(timeout=5)


def test_stop_during_startup_does_not_launch_child(project):
    root, logs, env, start, stop = project
    result = subprocess.run(
        ["bash", "-euc", 'source "$1"; load_env_files; expand_env_refs; process_init; '
         'touch() { local pid birth; read -r pid birth < "${1%/go}/pid"; '
         'kill -TERM -- "-$pid"; command touch "$@"; }; '
         'process_start early "$CTL_ROOT" bash -c \'echo launched > "$CTL_ROOT/started"\'; '
         'sleep 0.2', "bash", str(root / "scripts/common/_lib.sh")],
        env=env, cwd=root, text=True, capture_output=True, timeout=5,
    )
    assert result.returncode == 0, result.stderr
    assert not (root / "started").exists()
    assert not (logs / "run/early.process").exists()


@pytest.mark.parametrize("live", [True, False])
def test_legacy_pid_files_are_never_killed(project, live):
    root, logs, env, start, stop = project
    record = logs / "run/legacy.pid"
    record.parent.mkdir(parents=True)
    record.write_text(f"{os.getpid() if live else 99999999}\n")
    result = stop()
    assert (result.returncode != 0) == live
    assert record.exists() == live


def test_matching_identity_without_owned_group_is_refused(project):
    root, logs, env, start, stop = project
    assert os.getpgrp() != os.getpid()
    record = logs / "run/not-a-group.process"
    record.mkdir(parents=True)
    birth = Path(f"/proc/{os.getpid()}/stat").read_text().rsplit(") ", 1)[1].split()[19]
    (record / "pid").write_text(f"{os.getpid()} {birth}\n")
    result = stop()
    assert result.returncode != 0
    assert record.exists()
    assert not (root / "docker.calls").exists()
