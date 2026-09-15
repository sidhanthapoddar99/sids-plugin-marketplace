"""Simulated Docker lifecycle tests using recording shims; no daemon is exercised."""

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
COMMON = TEMPLATE / "scripts/common"
UP = TEMPLATE / "scripts/container/up.sh"

SHIM = r'''
import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ["CTL_ROOT"])
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
fixture = json.loads((root / "fixture.json").read_text())
services = fixture["model"]["services"]
if args[0] == "inspect":
    for container in args[3:]:
        service = container.removeprefix("scoped-")
        counter = root / (service + ".count")
        count = int(counter.read_text()) if counter.exists() else 0
        counter.write_text(str(count + 1))
        frames = fixture.get("states", {}).get(service, [{"Status": "running"}])
        state = frames[min(count, len(frames) - 1)]
        if state["Status"] == "running":
            state.setdefault("Health", {"Status": "healthy"})
        print(json.dumps(state))
    sys.exit(0)
if args[0] == "info":
    sys.exit(0)
commands = {"config", "version", "build", "up", "ps", "stop", "logs"}
command = next((part for part in args if part in commands), "")
if command == "config":
    if "--services" in args:
        print("\n".join(services))
    elif "--format" in args:
        print(json.dumps(fixture["model"]))
elif command == "build":
    if "--help" in args:
        print("--with-dependencies" if fixture.get("build_supported", True) else "build")
    else:
        sys.exit(fixture.get("build_exit", 0))
elif command == "up":
    time.sleep(fixture.get("up_delay", 0))
    sys.exit(fixture.get("up_exit", 0))
elif command == "ps":
    service = args[-1]
    if service not in fixture.get("missing", []):
        print("scoped-" + service)
elif command == "logs":
    print("fixture log stream", flush=True)
    if "logs_exit" in fixture:
        time.sleep(fixture.get("logs_delay", 0))
        sys.exit(fixture["logs_exit"])
    while True:
        time.sleep(0.1)
'''


def fixture_env(root: Path, services: dict, *, declared_checks: bool = True, **options: object) -> dict[str, str]:
    if declared_checks:
        services = {
            name: {"healthcheck": {"test": ["CMD", "fixture-ready"]}, **service}
            for name, service in services.items()
        }
    (root / "docker").mkdir()
    (root / "docker/compose.fixture.yaml").write_text("services: {}\n")
    (root / ".env").write_text("FIXTURE_ONLY=1\n")
    (root / "fixture.json").write_text(json.dumps({"model": {"services": services}, **options}))
    binary = root / "bin"
    binary.mkdir()
    docker = binary / "docker"
    docker.write_text(f"#!{sys.executable}\n" + SHIM)
    docker.chmod(0o755)
    return {
        "PATH": str(binary) + os.pathsep + os.environ["PATH"],
        "HOME": str(root),
        "CTL_ROOT": str(root),
        "NO_COLOR": "1",
    }


def command(*services: str, attach: int = 0, timeout: int = 3, schema: str = "") -> list[str]:
    return [
        "bash", "-c",
        'set -euo pipefail; source "$1/_lib.sh"; source "$1/_compose_start.sh"; '
        'read -r -a SCHEMA_SVCS <<< "$2" || true; '
        'mapfile -t compose_base < <(compose_argv -f docker/compose.fixture.yaml); '
        'shift 2; compose_start "$@"',
        "bash", str(COMMON), schema, str(attach), str(timeout), *services,
    ]


def run(env: dict[str, str], *services: str, **options: object) -> subprocess.CompletedProcess:
    return subprocess.run(command(*services, **options), env=env, text=True, capture_output=True, timeout=12)


def calls(root: Path, name: str) -> list[list[str]]:
    return [
        args for line in (root / "calls.jsonl").read_text().splitlines()
        if name in (args := json.loads(line)) and "--help" not in args
    ]


def test_build_failure_never_activates(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {"build": "."}}, build_exit=17)
    result = run(env, "api")
    assert result.returncode == 17, result.stderr
    assert not calls(tmp_path, "up")


def test_build_closure_precedes_activation_and_runtime_scope(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {
        "api": {"build": {"additional_contexts": {"base": "service:builder"}},
                "depends_on": {"db": {"condition": "service_healthy"}}},
        "db": {"build": ".", "healthcheck": {"test": ["CMD", "ready"]}},
        "builder": {"build": "."},
        "other": {"build": "."},
    }, states={"db": [{"Status": "running", "Health": {"Status": "healthy"}}]})
    result = run(env, "api")
    assert result.returncode == 0, result.stderr
    recorded = [json.loads(line) for line in (tmp_path / "calls.jsonl").read_text().splitlines()]
    build = calls(tmp_path, "build")[0]
    activation = calls(tmp_path, "up")[0]
    assert build[-3:] == ["build", "--with-dependencies", "api"]
    assert activation[-4:] == ["up", "-d", "--no-build", "api"]
    assert recorded.index(build) < recorded.index(activation)
    assert {entry[-1] for entry in calls(tmp_path, "ps")} == {"api", "db"}
    assert all("--project-directory" in entry for entry in calls(tmp_path, "ps"))
    assert all(entry[-1].startswith("scoped-") for entry in calls(tmp_path, "inspect"))


def test_all_services_build_without_subset(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}, "web": {}})
    assert run(env).returncode == 0
    assert calls(tmp_path, "build")[0][-2:] == ["build", "--with-dependencies"]
    assert {entry[-1] for entry in calls(tmp_path, "ps")} == {"api", "web"}


def test_missing_build_dependency_support_fails_before_activation(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, build_supported=False)
    result = run(env)
    assert result.returncode != 0
    assert "--with-dependencies is required" in result.stderr
    assert not calls(tmp_path, "build")
    assert not calls(tmp_path, "up")


@pytest.mark.parametrize("explicit", [True, False])
@pytest.mark.parametrize("exit_code", [0, 9])
def test_oneshot_completion_is_explicit_or_a_dependency_condition(
    tmp_path: Path, explicit: bool, exit_code: int,
) -> None:
    services = {"schema": {}}
    if not explicit:
        services["api"] = {"depends_on": {"schema": {"condition": "service_completed_successfully"}}}
    env = fixture_env(tmp_path, services, states={"schema": [
        {"Status": "running"}, {"Status": "exited", "ExitCode": exit_code},
    ]})
    result = run(env, schema="schema" if explicit else "")
    assert (result.returncode == 0) == (exit_code == 0), result.stderr
    assert not calls(tmp_path, "stop")


def test_zero_exit_of_long_running_service_is_failure(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, states={"api": [{"Status": "exited", "ExitCode": 0}]})
    assert run(env).returncode != 0


@pytest.mark.parametrize("state", [{"Status": "running", "Health": None}, {"Status": "running", "Health": {"Status": "starting"}}])
def test_declared_healthcheck_requires_health_and_times_out(tmp_path: Path, state: dict) -> None:
    env = fixture_env(tmp_path, {"api": {"healthcheck": {"test": ["CMD", "ready"]}}}, states={"api": [state]})
    result = run(env, timeout=1)
    assert result.returncode != 0
    assert "timed out" in result.stderr or "not ready" in result.stderr


def test_activation_wait_is_bounded(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, up_delay=30)
    before = time.monotonic()
    result = run(env, timeout=1)
    assert result.returncode != 0
    assert time.monotonic() - before < 5
    assert not calls(tmp_path, "stop")


def test_missing_replica_is_not_ready(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {"deploy": {"replicas": 2}}})
    assert run(env, timeout=1).returncode != 0


@pytest.mark.parametrize("service", [{}, {"healthcheck": {}}, {"healthcheck": {"disable": True}}, {"healthcheck": {"test": ["NONE"]}}])
def test_required_long_running_service_needs_declared_readiness(tmp_path: Path, service: dict) -> None:
    env = fixture_env(tmp_path, {"api": service}, declared_checks=False)
    result = run(env)
    assert result.returncode != 0
    assert "needs an enabled Compose readiness healthcheck" in result.stderr
    assert not calls(tmp_path, "build")
    assert not calls(tmp_path, "up")


def test_unhealthy_container_fails_readiness(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, states={"api": [
        {"Status": "running", "Health": {"Status": "unhealthy"}},
    ]})
    assert run(env).returncode != 0


@pytest.mark.parametrize("required", [True, False])
def test_optional_dependency_failure_only_blocks_when_required(tmp_path: Path, required: bool) -> None:
    env = fixture_env(tmp_path, {
        "api": {"depends_on": {"cache": {"required": required, "condition": "service_started"}}},
        "cache": {},
    }, states={"cache": [{"Status": "exited", "ExitCode": 4}]})
    result = run(env, "api")
    assert (result.returncode == 0) == (not required)
    if not required:
        assert "optional dependency cache" in result.stderr


def test_explicitly_selected_optional_dependency_is_required(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {
        "api": {"depends_on": {"cache": {"required": False}}}, "cache": {},
    }, missing=["cache"])
    assert run(env, "api", "cache", timeout=1).returncode != 0


def test_required_path_wins_over_optional_path(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {
        "api": {"depends_on": {"cache": {"required": False}, "worker": {}}},
        "worker": {"depends_on": {"cache": {}}}, "cache": {},
    }, missing=["cache"])
    assert run(env, "api", timeout=1).returncode != 0


def test_absent_optional_service_does_not_trigger_global_lookup(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {
        "api": {"depends_on": {"cache": {"required": False}}}, "cache": {},
    }, missing=["cache"])
    result = run(env, "api")
    assert result.returncode == 0, result.stderr
    assert [entry[-1] for entry in calls(tmp_path, "inspect")] == ["scoped-api"]


@pytest.mark.parametrize("exit_code", [0, 7])
def test_foreground_log_exit_is_propagated(tmp_path: Path, exit_code: int) -> None:
    env = fixture_env(tmp_path, {"api": {}}, logs_exit=exit_code)
    result = run(env, attach=1)
    assert result.returncode == (exit_code or 1), result.stderr
    assert "fixture log stream" in result.stdout
    assert not calls(tmp_path, "stop")


def test_foreground_successful_oneshot_logs_can_end_normally(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"schema": {}}, declared_checks=False, logs_exit=0,
                      states={"schema": [{"Status": "exited", "ExitCode": 0}]})
    result = run(env, attach=1, schema="schema")
    assert result.returncode == 0, result.stderr


def test_foreground_runtime_failure_does_not_roll_back(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, states={"api": [
        {"Status": "running"}, {"Status": "exited", "ExitCode": 8},
    ]})
    result = run(env, attach=1)
    assert result.returncode != 0
    assert not calls(tmp_path, "stop")


def test_log_stream_success_cannot_hide_container_exit(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, logs_exit=0, logs_delay=0.2, states={"api": [
        {"Status": "running"}, {"Status": "running"}, {"Status": "exited", "ExitCode": 0},
    ]})
    result = run(env, attach=1)
    assert result.returncode != 0
    assert not calls(tmp_path, "stop")


@pytest.mark.parametrize("phase", ["up", "logs"])
def test_foreground_interrupt_stops_only_selected_project_services(tmp_path: Path, phase: str) -> None:
    env = fixture_env(tmp_path, {"api": {"depends_on": {"db": {}}}, "db": {}, "other": {}},
                      up_delay=30 if phase == "up" else 0)
    process = subprocess.Popen(command("api", attach=1), env=env, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if (tmp_path / "calls.jsonl").exists() and calls(tmp_path, phase):
                break
            time.sleep(0.05)
        else:
            pytest.fail(f"foreground {phase} never started")
        os.killpg(process.pid, signal.SIGINT)
        process.communicate(timeout=5)
        assert process.returncode != 0
        stopped = calls(tmp_path, "stop")
        assert len(stopped) == 1
        assert stopped[0][-5:] == ["stop", "--timeout", "5", "api", "db"]
        assert "--project-directory" in stopped[0]
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()


def test_up_dry_run_never_builds_or_activates(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}})
    result = subprocess.run(["bash", str(UP), "--config", "fixture", "--nqa", "--dry-run"],
                            env=env, text=True, capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr
    assert "dry-run" in result.stdout
    assert not calls(tmp_path, "build")
    assert not calls(tmp_path, "up")


def test_up_runs_the_lifecycle_helper(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}}, build_exit=17)
    result = subprocess.run(["bash", str(UP), "--config", "fixture", "--nqa", "-y"],
                            env=env, text=True, capture_output=True, timeout=5)
    assert result.returncode == 17, result.stderr
    assert not calls(tmp_path, "up")


def test_up_rejects_blank_storage_before_any_docker_call(tmp_path: Path) -> None:
    env = fixture_env(tmp_path, {"api": {}})
    env["DATA_DIR"] = ""
    result = subprocess.run(["bash", str(UP), "--config", "fixture", "--nqa", "-y"],
                            env=env, text=True, capture_output=True, timeout=5)
    assert result.returncode != 0
    assert "DATA_DIR is blank" in result.stderr
    assert not (tmp_path / "calls.jsonl").exists()
