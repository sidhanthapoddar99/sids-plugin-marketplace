"""Deploy transcripts, ctl up --background, ctl up status, and the ctl check storage-folder rule.

A deploy is a ctl up with TAG=auto or a pinned tag. The suite runs the real up.sh and check.sh in a
scratch git repository, against the recording docker shim of test_up_lifecycle.py, so a refused run is
proven to reach no build, and a background run is proven to return before its child ends.
"""

import os
import pty
import re
import signal
import subprocess
import time
from pathlib import Path

import pytest

from test_deploy import CHECK, UP, commit, deploy_repo, up, write_record
from test_image_tag import git
from test_up_lifecycle import calls, fixture_env

NAME = re.compile(r"^\d{8}-\d{6}-(?P<tag>.+)\.log$")


def transcripts(root: Path) -> list[Path]:
    return sorted((root / "logs/deploy").glob("*.log"))


def only_transcript(root: Path) -> Path:
    found = transcripts(root)
    assert len(found) == 1, found
    return found[0]


def last_line(path: Path) -> str:
    return path.read_text().splitlines()[-1]


def status(env: dict[str, str], *flags: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(UP), "status", *flags], env=env, text=True, capture_output=True, timeout=20)


def background(env: dict[str, str], *flags: str, **shell: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(UP), "--config", "fixture", "--background", *flags],
                          env={**env, **shell}, text=True, capture_output=True, timeout=20)


def built(root: Path) -> bool:
    return (root / "calls.jsonl").exists() and bool(calls(root, "build"))


def wait_for(condition, seconds: float = 15) -> None:
    deadline = time.monotonic() + seconds
    while not condition():
        assert time.monotonic() < deadline, "timed out"
        time.sleep(0.1)


def birth(pid: int) -> str:
    return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def live_record(root: Path, process: subprocess.Popen) -> Path:
    """A process record for <process>, the way ctl up holds LOGS_DIR/run/up.process while it runs."""
    record = root / "logs/run/up.process"
    record.mkdir(parents=True)
    (record / "pid").write_text(f"{process.pid} {birth(process.pid)}\n")
    return record


def write_transcript(root: Path, name: str, *lines: str) -> Path:
    path = root / "logs/deploy" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(line + "\n" for line in ("transcript  logs/deploy/" + name, *lines)))
    return path


# ── the transcript ──

def test_a_deploy_writes_a_transcript_that_ends_with_its_result(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    path = only_transcript(tmp_path)
    head = git(tmp_path, "rev-parse", "--short=8", "HEAD")
    match = NAME.match(path.name)
    assert match and match["tag"] == head
    text = path.read_text()
    assert text.startswith(f"transcript  logs/deploy/{path.name}\ncommand     ctl up --config fixture --nqa -y\n")
    assert f"tag         auto → {head}\n" in text
    assert "startup ready: api" in text and "image retention:" in text   # it runs past startup, to the end
    assert last_line(path) == "result: ok"
    assert "startup ready: api" in result.stdout and "result: ok" in result.stdout   # the terminal still sees it
    assert "Plan" not in text   # it starts once the plan is settled
    assert not (tmp_path / "logs/run/up.process").exists()   # the deploy released its record


@pytest.mark.parametrize("tag", ["dev", "dev-slot-2", "none", "latest", None])
def test_a_local_run_writes_no_transcript(tmp_path: Path, tag: str | None) -> None:
    env = deploy_repo(tmp_path)
    result = up(env, **({} if tag is None else {"TAG": tag}))
    assert result.returncode == 0, result.stderr
    assert transcripts(tmp_path) == []


@pytest.mark.parametrize("flag", ["--dry-run", "--list"])
def test_dry_run_and_list_write_no_transcript(tmp_path: Path, flag: str) -> None:
    env = deploy_repo(tmp_path)
    assert up(env, flag, TAG="auto").returncode == 0
    assert transcripts(tmp_path) == []


def test_a_failed_build_records_its_exit(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, build_exit=17)
    result = up(env, TAG="auto")
    assert result.returncode == 17
    assert last_line(only_transcript(tmp_path)) == "result: failed (exit 17)"


def test_a_refused_deploy_records_its_error_and_keeps_stderr(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    older = git(tmp_path, "rev-parse", "HEAD")
    write_record(tmp_path, commit(tmp_path, "newer"))
    result = up(env, TAG=older[:8])
    assert result.returncode == 1
    assert "is a rollback" in result.stderr and "is a rollback" not in result.stdout   # stderr stays stderr
    path = only_transcript(tmp_path)
    assert "is a rollback" in path.read_text()
    assert last_line(path) == "result: failed (exit 1)"


def test_a_terminated_deploy_records_the_signal(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, up_delay=5)
    process = subprocess.Popen(["bash", str(UP), "--config", "fixture", "--nqa", "-y"], env={**env, "TAG": "auto"},
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_for(lambda: (tmp_path / "calls.jsonl").exists() and bool(calls(tmp_path, "up")))
    os.killpg(process.pid, signal.SIGTERM)
    assert process.wait(timeout=15) == 143
    assert last_line(only_transcript(tmp_path)) == "result: failed (exit 143)"


def test_the_terminal_keeps_its_colours_and_the_transcript_has_none(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    del env["NO_COLOR"]
    master, terminal = pty.openpty()
    process = subprocess.Popen(["bash", str(UP), "--config", "fixture", "--nqa", "-y"],
                               env={**env, "TAG": "auto", "TERM": "xterm"},
                               stdin=subprocess.DEVNULL, stdout=terminal, stderr=terminal)
    os.close(terminal)
    seen = b""
    while True:
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        seen += chunk
    os.close(master)
    assert process.wait(timeout=20) == 0
    assert b"\x1b[" in seen.split(b"transcript  ", 1)[1]   # colour codes after the transcript began
    text = only_transcript(tmp_path).read_text()
    assert "startup ready: api" in text and "\x1b" not in text


def test_attach_keeps_the_container_log_stream_out_of_the_transcript(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, logs_exit=0)
    result = up(env, "-a", TAG="auto")
    assert "fixture log stream" in result.stdout, result.stdout + result.stderr
    text = only_transcript(tmp_path).read_text()
    assert "startup ready: api" in text
    assert "fixture log stream" not in text
    assert last_line(only_transcript(tmp_path)).startswith("result: ")


@pytest.mark.parametrize("folder", ["logs", "data"])
def test_a_folder_the_user_cannot_write_stops_a_deploy_before_the_build(tmp_path: Path, folder: str) -> None:
    if os.geteuid() == 0:
        pytest.skip("root writes every folder")
    env = deploy_repo(tmp_path)
    locked = tmp_path / folder
    locked.mkdir()
    locked.chmod(0o555)
    try:
        result = up(env, TAG="auto")
        assert result.returncode != 0
        assert f"{locked} is not writable by" in result.stderr
        assert f"sudo chown {owner()} {locked}" in result.stderr
        assert "stops before the build" in result.stderr
        assert not built(tmp_path)
        local = up(env, TAG="dev")   # a local run writes no transcript, so the folder does not stop it
        assert local.returncode == 0, local.stderr
    finally:
        locked.chmod(0o755)


def owner() -> str:
    user = subprocess.run(["id", "-un"], text=True, capture_output=True, check=True).stdout.strip()
    group = subprocess.run(["id", "-gn"], text=True, capture_output=True, check=True).stdout.strip()
    return f"{user}:{group}"


# ── --background ──

def test_background_returns_at_once_and_the_child_finishes_the_transcript(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, up_delay=2)
    started = time.monotonic()
    result = background(env, "-y", TAG="auto")
    assert result.returncode == 0, result.stderr
    assert time.monotonic() - started < 1.8   # the activation alone takes 2 s
    path = only_transcript(tmp_path)
    assert f"transcript  logs/deploy/{path.name}" in result.stdout
    assert "ctl up status -f" in result.stdout
    running = status(env)
    assert running.returncode == 0 and "state       running" in running.stdout, running.stdout + running.stderr
    followed = status(env, "-f")
    assert followed.returncode == 0, followed.stdout + followed.stderr
    assert followed.stdout.rstrip().endswith("state  succeeded")
    text = path.read_text()
    assert text.startswith(f"transcript  logs/deploy/{path.name}\ncommand     ctl up --config fixture -y --nqa\n")
    assert "startup ready: api" in text and last_line(path) == "result: ok"
    assert (tmp_path / "data/deployed-commit").exists()


def test_background_writes_a_transcript_for_a_local_tag_too(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    assert background(env, "-y", TAG="dev").returncode == 0
    path = only_transcript(tmp_path)
    assert NAME.match(path.name)["tag"] == "dev"
    wait_for(lambda: last_line(path).startswith("result: "))
    assert last_line(path) == "result: ok"


def test_a_failing_background_run_records_its_exit(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, build_exit=9)
    assert background(env, "-y", TAG="auto").returncode == 0
    followed = status(env, "-f")
    assert followed.returncode == 9
    assert followed.stdout.rstrip().endswith("state  failed (exit 9)")
    assert status(env).returncode == 1


@pytest.mark.parametrize(("flags", "message"), [
    ([], "--background needs -y"),
    (["-y", "-a"], "--background cannot attach (-a)"),
    (["-y", "--dry-run"], "--background with --dry-run or --list starts nothing"),
    (["-y", "--list"], "--background with --dry-run or --list starts nothing"),
])
def test_background_refuses_what_needs_a_terminal(tmp_path: Path, flags: list[str], message: str) -> None:
    env = deploy_repo(tmp_path)
    result = background(env, *flags, TAG="auto")
    assert result.returncode != 0
    assert message in result.stderr
    assert transcripts(tmp_path) == [] and not built(tmp_path)


def test_background_refuses_set_preset(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = subprocess.run(["bash", str(UP), "set-preset", "prod", "--config", "fixture", "-y", "--background"],
                            env=env, text=True, capture_output=True, timeout=20)
    assert result.returncode != 0
    assert "--background runs a stack, and set-preset saves one" in result.stderr


@pytest.mark.parametrize("second", ["foreground", "background"])
def test_a_running_deploy_blocks_another(tmp_path: Path, second: str) -> None:
    env = deploy_repo(tmp_path, up_delay=4)
    first = subprocess.Popen(["bash", str(UP), "--config", "fixture", "--nqa", "-y"], env={**env, "TAG": "auto"},
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        wait_for(lambda: (tmp_path / "calls.jsonl").exists() and bool(calls(tmp_path, "up")))
        builds = len(calls(tmp_path, "build"))
        result = up(env, TAG="auto") if second == "foreground" else background(env, "-y", TAG="dev")
        assert result.returncode != 0
        assert "another ctl up is still running" in result.stderr
        assert len(calls(tmp_path, "build")) == builds
        assert len(transcripts(tmp_path)) == 1
        assert "state       running" in status(env).stdout
    finally:
        os.killpg(first.pid, signal.SIGTERM)
        first.wait(timeout=15)


def test_a_record_whose_process_ended_does_not_block(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    ended = subprocess.Popen(["true"])
    record = live_record(tmp_path, ended)
    ended.wait()
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert not record.exists()


# ── ctl up status ──

def test_status_without_a_transcript_says_so(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = status(env)
    assert result.returncode == 1
    assert "no deploy transcript yet in logs/deploy" in result.stdout


def test_status_reports_a_success_with_its_tag_start_and_record(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    assert up(env, TAG="auto").returncode == 0
    result = status(env)
    assert result.returncode == 0, result.stdout + result.stderr
    head = git(tmp_path, "rev-parse", "HEAD")
    assert f"tag         {head[:8]}" in result.stdout
    assert re.search(r"started     \d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC", result.stdout)
    assert f"deployed    {head} (data/deployed-commit)" in result.stdout
    assert "state       succeeded" in result.stdout
    assert result.stdout.rstrip().endswith("result: ok")   # the last lines of the transcript


def test_status_reads_the_newest_transcript_and_reports_a_failure(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    write_transcript(tmp_path, "20261028-090000-aaaaaaaa.log", "result: ok")
    write_transcript(tmp_path, "20261029-090000-bbbbbbbb.log", "result: failed (exit 4)")
    result = status(env)
    assert result.returncode == 1
    assert "tag         bbbbbbbb" in result.stdout
    assert "started     2026-10-29 09:00:00 UTC" in result.stdout
    assert "deployed    none yet" in result.stdout
    assert "state       failed (exit 4)" in result.stdout
    followed = status(env, "-f")
    assert followed.returncode == 4


def test_status_reports_a_run_that_ended_without_a_result_as_interrupted(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, up_delay=5)
    process = subprocess.Popen(["bash", str(UP), "--config", "fixture", "--nqa", "-y"], env={**env, "TAG": "auto"},
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_for(lambda: (tmp_path / "calls.jsonl").exists() and bool(calls(tmp_path, "up")))
    os.killpg(process.pid, signal.SIGKILL)   # no trap runs: the power went, or the kernel killed it
    process.wait(timeout=15)
    assert not last_line(only_transcript(tmp_path)).startswith("result: ")
    result = status(env)
    assert result.returncode == 1
    assert "state       interrupted" in result.stdout
    assert status(env, "-f").returncode == 1


def test_status_follow_waits_for_a_running_deploy_and_exits_with_its_result(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    path = write_transcript(tmp_path, "20261029-100000-cccccccc.log", "▸ docker compose build")
    writer = subprocess.Popen(["bash", "-c", 'sleep 1.5; printf "result: failed (exit 3)\\n" >> "$1"', "bash", str(path)])
    live_record(tmp_path, writer)
    try:
        plain = status(env)
        assert plain.returncode == 0 and "state       running" in plain.stdout, plain.stdout + plain.stderr
        followed = status(env, "-f")
        assert followed.returncode == 3, followed.stdout + followed.stderr
        assert "result: failed (exit 3)" in followed.stdout
        assert followed.stdout.rstrip().endswith("state  failed (exit 3)")
    finally:
        writer.wait(timeout=10)


def test_status_takes_no_other_argument(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = status(env, "prod")
    assert result.returncode != 0
    assert "unknown argument: prod (try ctl up status --help)" in result.stderr


# ── ctl check: the storage folders ──

def check(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(CHECK)], env=env, text=True, capture_output=True, timeout=60)


def test_check_passes_storage_folders_the_user_can_write(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {"build": ".", "image": "example/api:dev", "pull_policy": "never"}})
    (tmp_path / "logs/backups").mkdir(parents=True)
    (tmp_path / "data").mkdir()
    result = check(env)
    assert "DATA_DIR, LOGS_DIR and BACKUP_DIR derive from BASE_DIR, and " in result.stdout, result.stdout + result.stderr
    assert "can write each" in result.stdout
    assert "_DIR —" not in result.stderr


def test_check_names_a_missing_storage_folder(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {"build": ".", "image": "example/api:dev", "pull_policy": "never"}})
    (tmp_path / "data").mkdir()
    result = check(env)
    assert result.returncode != 0
    assert f".env: LOGS_DIR — {tmp_path}/logs does not exist; ctl setup env creates it" in result.stderr
    assert f".env: BACKUP_DIR — {tmp_path}/logs/backups does not exist; ctl setup env creates it" in result.stderr
    assert "can write each" not in result.stdout


def test_check_names_the_chown_for_a_folder_the_user_cannot_write(tmp_path: Path) -> None:
    if os.geteuid() == 0:
        pytest.skip("root writes every folder")
    env = fixture_env(tmp_path, {"api": {"build": ".", "image": "example/api:dev", "pull_policy": "never"}})
    (tmp_path / "logs/backups").mkdir(parents=True)
    (tmp_path / "data").mkdir()
    (tmp_path / "data").chmod(0o555)
    try:
        result = check(env)
    finally:
        (tmp_path / "data").chmod(0o755)
    assert result.returncode != 0
    assert (f".env: DATA_DIR — {tmp_path}/data is not writable by {owner().split(':')[0]}; "
            f"the deploy user must own it: sudo chown {owner()} {tmp_path}/data") in result.stderr
