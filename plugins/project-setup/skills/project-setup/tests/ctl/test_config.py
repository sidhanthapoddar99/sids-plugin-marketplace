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
    # .env.template.synced records the template .env matched, so the next run can tell its comments apart.
    assert sorted(path.name for path in tmp_path.glob(".env*")) == [".env", ".env.template", ".env.template.synced"]
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
    (root / "CLAUDE.md").write_text("@AGENTS.md\n")
    (root / "scripts/gate").mkdir(parents=True)
    (root / "scripts/gate/all.sh").write_text("RUNGS=(lint typecheck test check)\n")
    subprocess.run(["git", "init", "-q", str(root)], check=True)


def test_check_accepts_mixed_setting_kinds_and_blank_secrets(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\nDEBUG=0\nBASE_DIR=.\nDATA_DIR=${BASE_DIR}/data\nJWT_SIGNING_KEY=\n")
    result = run_worker(tmp_path, CHECK)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize(
    ("setup", "failure"),
    [
        (lambda root: (root / "CLAUDE.md").unlink(), "CLAUDE.md missing — write it as the one line '@AGENTS.md'"),
        (lambda root: (root / "CLAUDE.md").write_text("Read AGENTS.md first.\n"), "CLAUDE.md must be exactly '@AGENTS.md'"),
        (lambda root: ((root / "CLAUDE.md").unlink(), (root / "CLAUDE.md").symlink_to("AGENTS.md")), "CLAUDE.md missing"),
        (lambda root: ((root / "apps/api/AGENTS.md").write_text("# API\n")), "apps/api/CLAUDE.md missing"),
        (lambda root: ((root / "apps/web").mkdir(), (root / "apps/web/CLAUDE.md").write_text("@AGENTS.md\n")), "apps/web/CLAUDE.md has no AGENTS.md beside it"),
        (lambda root: (root / "AGENTS.md").write_text("| Gate ladder | `lint typecheck test check` |\n" + "line\n" * 200), "AGENTS.md has 201 lines; the limit is 200"),
        (lambda root: (root / "AGENTS.md").write_text("| Gate ladder | `lint typecheck test check` |\nDecided on 2026-10-20.\n"), "AGENTS.md:2 holds a date"),
        (lambda root: ((root / "apps/api/AGENTS.md").write_text("x" * 33000 + "\n"), (root / "apps/api/CLAUDE.md").write_text("@AGENTS.md\n")), "the limit is 32768"),
    ],
)
def test_check_enforces_the_brief(tmp_path: Path, setup, failure: str) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    setup(tmp_path)
    result = run_worker(tmp_path, CHECK)
    assert result.returncode != 0
    assert failure in result.stderr


def test_check_caps_source_files_unless_recorded(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    (tmp_path / "apps/api/big.py").write_text("x = 1\n" * 501)
    (tmp_path / "apps/api/generated").mkdir()
    (tmp_path / "apps/api/generated/schema.ts").write_text("x;\n" * 900)
    result = run_worker(tmp_path, CHECK)
    assert "apps/api/big.py has 501 lines; split it" in result.stderr
    assert "schema.ts" not in result.stderr
    with (tmp_path / "AGENTS.md").open("a") as brief:
        brief.write("## Exceptions to the standard layout\n\n- size-cap apps/api/big.py: one generated-by-hand table.\n")
    result = run_worker(tmp_path, CHECK)
    assert "big.py" not in result.stderr, result.stderr


def test_check_refuses_code_that_names_a_doc_page_or_tracker_issue(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    (tmp_path / "apps/api/main.py").write_text("# see references/02_env.md\nx = 1\n# data/tasks/2026-01-01-auth/issue.md\n")
    (tmp_path / "apps/api/README.md").write_text("Rules: references/02_env.md\n")
    result = run_worker(tmp_path, CHECK)
    assert "apps/api/main.py:1 names a doc page or tracker issue" in result.stderr
    assert "apps/api/main.py:3 names a doc page or tracker issue" in result.stderr
    assert "README.md" not in result.stderr


def git_commit(root: Path, message: str) -> None:
    identity = ["-c", "user.name=fixture", "-c", "user.email=fixture@invalid"]
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), *identity, "commit", "-qm", message], check=True)


def test_check_refuses_an_edit_to_a_migration_on_the_default_branch(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    subprocess.run(["git", "-C", str(tmp_path), "checkout", "-qb", "main"], check=True)
    migrations = tmp_path / "apps/database/postgres/migrations"
    migrations.mkdir(parents=True)
    (migrations / "V1__start.sql").write_text("CREATE TABLE a (id int);\n")
    git_commit(tmp_path, "base")
    subprocess.run(["git", "-C", str(tmp_path), "checkout", "-qb", "work"], check=True)
    (migrations / "V2__next.sql").write_text("CREATE TABLE b (id int);\n")
    result = run_worker(tmp_path, CHECK)
    assert "no migration on main is changed or deleted" in result.stdout, result.stdout + result.stderr
    (migrations / "V1__start.sql").write_text("CREATE TABLE a (id bigint);\n")
    git_commit(tmp_path, "edit")
    result = run_worker(tmp_path, CHECK)
    assert "V1__start.sql is on main, so a database may have applied it" in result.stderr
    (migrations / "V1__start.sql").write_text("CREATE TABLE a (id int);\n")
    (migrations / "V2__next.sql").unlink()
    git_commit(tmp_path, "restore")
    assert "V1__start.sql" not in run_worker(tmp_path, CHECK).stderr


def test_check_accepts_an_agents_file_with_its_claude_import(tmp_path: Path) -> None:
    scaffold_check(tmp_path, "API_PORT=8000\n")
    (tmp_path / "apps/api/AGENTS.md").write_text("# API\n")
    (tmp_path / "apps/api/CLAUDE.md").write_text("@AGENTS.md\n")
    result = run_worker(tmp_path, CHECK)
    assert "2 AGENTS.md file(s)" in result.stdout, result.stdout + result.stderr
    assert "CLAUDE.md" not in result.stderr


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


@pytest.mark.parametrize(("local", "failure"), [
    ("CTL_RUST_DEBUG=line-tables-only\n", None),
    ("CTL_RUST_DEBUG=\n", None),
    ("CTL_RUST_DEBUG=maximum\n", "CTL_RUST_DEBUG=maximum is not a debug level Cargo accepts"),
], ids=["a-level", "empty", "refused"])
def test_check_names_a_rust_debug_level_cargo_would_refuse(tmp_path: Path, local: str, failure: str | None) -> None:
    root = tmp_path / "repo"
    scaffold_check(root, "API_PORT=8000\n" + STORAGE + "CTL_RUST_DEBUG=\n")
    result = run_check(root, "API_PORT=8000\n" + STORAGE + local)
    if failure is None:
        assert result.returncode == 0, result.stdout + result.stderr
    else:
        assert result.returncode != 0
        assert failure in result.stderr
