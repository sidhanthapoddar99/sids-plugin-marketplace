"""Exercise setup and conformance checks in isolated generated repositories."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from test_stack import run_lib, run_worker

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
SETUP = TEMPLATE / "scripts/config/setup.sh"
CHECK = TEMPLATE / "scripts/config/check.sh"


def test_setup_creates_one_file_and_preserves_values_on_rerun(tmp_path: Path) -> None:
    shutil.copy(TEMPLATE / ".env.template", tmp_path)
    (tmp_path / ".mise.toml").write_text('python = "<version>"\n')
    first = run_worker(tmp_path, SETUP)
    assert first.returncode == 1
    assert "toolchains were not installed" in first.stderr
    assert sorted(path.name for path in tmp_path.glob(".env*")) == [".env", ".env.template"]
    original = (tmp_path / ".env").read_text()
    assert "POSTGRES_PASSWORD= " not in original
    assert "JWT_SIGNING_KEY= " not in original
    assert "# OPENAI_API_KEY=" in original
    assert "DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}" in original
    assert (tmp_path / ".env.template").read_text() == (TEMPLATE / ".env.template").read_text()
    with (tmp_path / ".env.template").open("a") as handle:
        handle.write("NEW_DEBUG_FLAG=0\n")
    second = run_worker(tmp_path, SETUP)
    assert second.returncode == 1
    assert (tmp_path / ".env").read_text() == original + "NEW_DEBUG_FLAG=0\n"
    schema = run_lib(tmp_path, "check_env_schema")
    assert schema.returncode == 0, schema.stderr
    resolved = run_lib(tmp_path, 'require_env; [[ $DATABASE_URL != *\'${\'* && $BACKUP_DIR == ./logs/backups ]]')
    assert resolved.returncode == 0, resolved.stderr


def scaffold_check(root: Path, body: str) -> None:
    (root / "apps/api").mkdir(parents=True)
    (root / "apps/api/config.yaml").write_text("server:\n  port: ${API_PORT}\n")
    (root / ".env.template").write_text(body)
    (root / "AGENTS.md").write_text("| Gate ladder | `lint typecheck test check` |\n")
    (root / "scripts/gate").mkdir(parents=True)
    (root / "scripts/gate/all.sh").write_text("RUNGS=(lint typecheck test check)\n")
    subprocess.run(["git", "init", "-q", str(root)], check=True)


def test_check_accepts_mixed_setting_kinds_and_blank_secrets(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\nDEBUG=0\nBASE_DIR=.\nDATA_DIR=${BASE_DIR}/data\nJWT_SIGNING_KEY=\n")
    result = run_worker(tmp_path, CHECK)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("as_symlink", [False, True])
def test_check_rejects_root_claude_file(tmp_path: Path, as_symlink: bool) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    claude = tmp_path / "CLAUDE.md"
    if as_symlink:
        claude.symlink_to("AGENTS.md")
    else:
        claude.write_text("@AGENTS.md\n")
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert "CLAUDE.md exists at the repo root" in result.stderr


@pytest.mark.parametrize(
    ("body", "failure"),
    [
        ("API_PORT=8000\nAPI_PORT=9000\n", "duplicate key API_PORT"),
        ("API_PORT=8000\nJWT_SIGNING_KEY=fixture-secret\n", "JWT_SIGNING_KEY must be blank"),
        ("DEBUG=0\n", "not in .env.template"),
        ("", "not in .env.template"),
    ],
)
def test_check_rejects_invalid_contract(tmp_path: Path, body: str, failure: str) -> None:
    scaffold_check(tmp_path, body)
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert failure in result.stderr
    assert "fixture-secret" not in result.stdout + result.stderr


@pytest.mark.parametrize("name", [".env", ".env.local", ".env.extra.template"])
def test_check_rejects_tracked_env_except_root_template(tmp_path: Path, name: str) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    (tmp_path / name).write_text("API_PORT=9000\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", name, ".env.template"], check=True)
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert f"{name} is tracked by git" in result.stderr


def test_root_template_is_trackable_and_local_env_is_ignored(tmp_path: Path) -> None:
    shutil.copy(TEMPLATE / ".gitignore", tmp_path)
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    result = subprocess.run(
        ["git", "-C", str(tmp_path), "check-ignore", ".env", ".env.local", ".env.template", "apps/web/.env.template"],
        capture_output=True, text=True, check=False,
    )
    assert result.stdout.splitlines() == [".env", ".env.local", "apps/web/.env.template"]


STORAGE = "BASE_DIR=.\nDATA_DIR=${BASE_DIR}/data\nLOGS_DIR=${BASE_DIR}/logs\nBACKUP_DIR=${LOGS_DIR}/backups\n"


def run_check(root: Path, local_env: str | None = None) -> subprocess.CompletedProcess[str]:
    """Run ctl check with docker reported as stopped, so only the repo and env rules decide."""
    if local_env is not None:
        (root / ".env").write_text(local_env)
    fake = root.parent / "fake-bin"
    fake.mkdir(exist_ok=True)
    (fake / "docker").write_text("#!/bin/sh\nexit 1\n")
    (fake / "docker").chmod(0o755)
    (root / "scripts/common").symlink_to(TEMPLATE / "scripts/common", target_is_directory=True)
    env = {"PATH": f"{fake}:{os.environ['PATH']}", "HOME": str(root), "NO_COLOR": "1", "CTL_ROOT": str(root)}
    return subprocess.run(["bash", str(CHECK)], env=env, capture_output=True, text=True, check=False)


@pytest.mark.parametrize("storage", [
    STORAGE,
    "BASE_DIR=/srv/app\nDATA_DIR=${BASE_DIR}\nLOGS_DIR=${BASE_DIR}/logs\nBACKUP_DIR=${BASE_DIR}/backups\n",
    "",
], ids=["shipped", "other-derivations", "no-storage-keys"])
def test_check_accepts_storage_derived_from_base_dir(tmp_path: Path, storage: str) -> None:
    root = tmp_path / "repo"
    scaffold_check(root, "API_PORT=8000\n" + storage)
    result = run_check(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "derive from BASE_DIR" in result.stdout


@pytest.mark.parametrize(("storage", "failure"), [
    (STORAGE.replace("${BASE_DIR}/data", "./data"), "DATA_DIR=./data does not derive from ${BASE_DIR}"),
    (STORAGE.replace("${LOGS_DIR}/backups", "./logs/backups"), "BACKUP_DIR=./logs/backups does not derive"),
    ("DATA_DIR=${BASE_DIR}/data\nBASE_DIR=.\n", "DATA_DIR reads ${BASE_DIR}, which is not declared above it"),
    ("BACKUP_DIR=${LOGS_DIR}/backups\nBASE_DIR=.\nLOGS_DIR=${BASE_DIR}/logs\n",
     "BACKUP_DIR reads ${LOGS_DIR}, which is not declared above it"),
], ids=["data-literal", "backup-literal", "base-below", "logs-below"])
def test_check_rejects_a_template_path_that_leaves_base_dir(tmp_path: Path, storage: str, failure: str) -> None:
    root = tmp_path / "repo"
    scaffold_check(root, "API_PORT=8000\n" + storage)
    result = run_check(root)
    assert result.returncode != 0
    assert failure in result.stderr


@pytest.mark.parametrize(("local", "failure"), [
    (STORAGE, None),
    (STORAGE.replace("BASE_DIR=.", "BASE_DIR=/srv/app").replace("${BASE_DIR}/data", "/mnt/fast/data"), None),
    (STORAGE.replace("BASE_DIR=.", "BASE_DIR=/srv/app").replace("${BASE_DIR}/logs", "./logs"),
     "LOGS_DIR=./logs resolves to {root}/logs, outside BASE_DIR (/srv/app)"),
    (STORAGE.replace("BASE_DIR=.", "BASE_DIR=./state").replace("${BASE_DIR}/data", "./data"),
     "DATA_DIR=./data resolves to {root}/data, outside BASE_DIR ({root}/state)"),
], ids=["derived", "absolute-is-deliberate", "stale-logs", "stale-data"])
def test_check_names_a_local_relative_path_left_behind_by_base_dir(
    tmp_path: Path, local: str, failure: str | None
) -> None:
    root = tmp_path / "repo"
    scaffold_check(root, "API_PORT=8000\n" + STORAGE)
    result = run_check(root, "API_PORT=8000\n" + local)
    if failure is None:
        assert result.returncode == 0, result.stdout + result.stderr
    else:
        assert result.returncode != 0
        assert failure.format(root=root) in result.stderr
