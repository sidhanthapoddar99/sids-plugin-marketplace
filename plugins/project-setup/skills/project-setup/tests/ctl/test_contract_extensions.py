"""Cross-cutting conformance checks against small synthetic repositories."""

import os
import subprocess
from pathlib import Path

import pytest

from test_config import CHECK, TEMPLATE, scaffold_check
from test_stack import run_worker
from test_setup_runtime import fake_mise, fake_tool, scaffold


@pytest.mark.parametrize("filename", ["generated-credentials.conf", "required-credentials.conf"])
def test_declared_token_template_values_must_be_blank(tmp_path: Path, filename: str) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\nSERVICE_TOKEN=synthetic-private-value\n")
    directory = tmp_path / "scripts/config"
    directory.mkdir()
    declaration = "SERVICE_TOKEN hex32\n" if filename.startswith("generated") else "SERVICE_TOKEN\n"
    (directory / filename).write_text(declaration)
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert "SERVICE_TOKEN must be blank" in result.stderr
    assert "synthetic-private-value" not in result.stdout + result.stderr


def test_version_checks_find_nested_sources_and_ignore_dependency_manifests(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    for directory in ("node_modules", "target", ".venv", "vendor", "generated"):
        decoy = tmp_path / "apps/packages/library" / directory / "dependency/Cargo.toml"
        decoy.parent.mkdir(parents=True)
        decoy.write_text('version = "<version>"\n')
    result = run_worker(tmp_path, CHECK)
    assert result.returncode == 0, result.stdout + result.stderr
    manifest = tmp_path / "apps/packages/library/crates/real/Cargo.toml"
    manifest.parent.mkdir(parents=True)
    manifest.write_text('version = "<version>"\n')
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert "crates/real/Cargo.toml still holds" in result.stderr
    assert "dependency/Cargo.toml still holds" not in result.stderr


def test_cli_build_failure_is_not_reported_as_success(tmp_path: Path) -> None:
    (tmp_path / "apps/example-tui-go").mkdir(parents=True)
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts/common").symlink_to(TEMPLATE / "scripts/common", target_is_directory=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    compiler = binaries / "go"
    compiler.write_text('#!/bin/sh\n[ "$1" = version ] && exit 0\nexit 37\n')
    compiler.chmod(0o755)
    result = subprocess.run(
        ["bash", str(TEMPLATE / "scripts/container/build.sh"), "cli"],
        env={"PATH": f"{binaries}:{os.environ['PATH']}", "HOME": str(tmp_path),
             "CTL_ROOT": str(tmp_path), "NO_COLOR": "1"},
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 37
    assert "✓" not in result.stdout


def test_app_command_keeps_environment_text_literal(tmp_path: Path) -> None:
    binaries = tmp_path / "bin"
    binaries.mkdir()
    runner = binaries / "uv"
    runner.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
    runner.chmod(0o755)
    host = "localhost $(touch marker) ; echo unexpected"
    result = subprocess.run(
        ["bash", "-euc", 'source "$1"; source "$2"; bash -c "$(app_cmd api)"', "bash",
         str(TEMPLATE / "scripts/common/_lib.sh"), str(TEMPLATE / "scripts/dev/_apps.sh")],
        cwd=tmp_path,
        env={"PATH": f"{binaries}:{os.environ['PATH']}", "CTL_ROOT": str(tmp_path),
             "API_HOST": host, "API_PORT": "8123", "NO_COLOR": "1"},
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    arguments = result.stdout.splitlines()
    assert arguments[arguments.index("--host") + 1] == host
    assert not (tmp_path / "marker").exists()


@pytest.mark.parametrize("app,expected", [("api", ["uv", "curl"]),
                                         ("engine", ["cargo", "bun", "watchexec", "curl"]),
                                         ("app", ["bun", "curl"])])
def test_example_app_requirements_are_targeted(app: str, expected: list[str]) -> None:
    result = subprocess.run(
        ["bash", "-euc", 'source "$1"; app_tools "$2"', "bash",
         str(TEMPLATE / "scripts/dev/_apps.sh"), app],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == expected


@pytest.mark.parametrize("worker", ["gate/lint.sh", "gate/typecheck.sh", "test/test.sh"])
@pytest.mark.parametrize("broken", [False, True])
def test_targeted_gate_activates_only_its_runtime(tmp_path: Path, worker: str, broken: bool) -> None:
    scaffold(tmp_path)
    fake_mise(tmp_path)
    fake_tool(tmp_path, "bun", '[[ "$1" == --version ]] || exit 9' if broken else "")
    frontend = tmp_path / "apps/example-single-web-app-vite"
    frontend.mkdir(parents=True)
    (frontend / "example.test.ts").write_text("")
    result = subprocess.run(
        ["/bin/bash", str(tmp_path / "scripts" / worker), "single"],
        env={"PATH": str(tmp_path / "bin"), "HOME": str(tmp_path),
             "CTL_ROOT": str(tmp_path), "NO_COLOR": "1"},
        capture_output=True, text=True, check=False,
    )
    assert (result.returncode != 0) == broken, result.stdout + result.stderr
    assert (tmp_path / "mise.calls").read_text().splitlines() == ["env -s bash"]
    calls = (tmp_path / "tool.calls").read_text()
    assert "bun|" in calls and "|run " in calls
    assert all(line.startswith("bun|") for line in calls.splitlines())
