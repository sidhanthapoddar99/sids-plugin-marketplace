"""ctl env loading: every ${NAME} in the three env files resolves before compose or an app sees it.

The suite runs the real shell library (scripts/common/_lib.sh) in a scratch root, so it proves the
loader itself and not a copy of it. Compose keeps a value the shell hands it as it is, so a
reference left unresolved becomes a volume named `${DATA_DIR}/postgres` or a database URL that
holds `${POSTGRES_USER}` as text.
"""

import os
import subprocess
from pathlib import Path

import pytest

ENV_FILES = (".env.secrets", ".env.data", ".env.proxy")


LIB = Path(__file__).resolve().parents[2] / "template/scripts/common/_lib.sh"

# source the library, load the three files the way every ctl verb does, then print the asked keys
SCRIPT = (
    'source "$1"; shift; cd "$CTL_ROOT"; require_env; '
    'for k in "$@"; do printf "%s=%s\\n" "$k" "${!k}"; done'
)

Files = dict[str, str]
Values = dict[str, str]


def load_env(
    root: Path, files: Files, keys: list[str], shell: Values | None = None
) -> tuple[subprocess.CompletedProcess[str], Values]:
    for name in ENV_FILES:
        (root / name).write_text(files.get(name, ""))
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", str(root)), "NO_COLOR": "1"}
    env.update(shell or {})
    env["CTL_ROOT"] = str(root)
    result = subprocess.run(
        ["bash", "-c", SCRIPT, "bash", str(LIB), *keys],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    return result, values


DATA = """\
DATA_DIR=./data
LOGS_DIR=./logs
BACKUP_DIR=${LOGS_DIR}/backups
POSTGRES_DIR=${DATA_DIR}/postgres
"""

SECRETS = """\
POSTGRES_USER=app
POSTGRES_PASSWORD=pw
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=app
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
"""

PROXY = """\
ENGINE_HOST=localhost
ENGINE_PORT=8080
ENGINE_URL=http://${ENGINE_HOST}:${ENGINE_PORT}
"""


def test_nested_paths_resolve(tmp_path: Path) -> None:
    result, values = load_env(tmp_path, {".env.data": DATA}, ["BACKUP_DIR", "POSTGRES_DIR"])
    assert result.returncode == 0, result.stderr
    assert values == {"BACKUP_DIR": "./logs/backups", "POSTGRES_DIR": "./data/postgres"}


def test_a_key_set_in_the_shell_wins_and_is_what_gets_expanded(tmp_path: Path) -> None:
    shell = {"DATA_DIR": "/srv/app/data"}
    result, values = load_env(tmp_path, {".env.data": DATA}, ["DATA_DIR", "POSTGRES_DIR"], shell)
    assert result.returncode == 0, result.stderr
    assert values == {"DATA_DIR": "/srv/app/data", "POSTGRES_DIR": "/srv/app/data/postgres"}


def test_references_cross_the_three_files(tmp_path: Path) -> None:
    files = {".env.secrets": SECRETS, ".env.proxy": PROXY}
    result, values = load_env(tmp_path, files, ["DATABASE_URL", "ENGINE_URL"])
    assert result.returncode == 0, result.stderr
    assert values == {
        "DATABASE_URL": "postgresql://app:pw@localhost:5432/app",
        "ENGINE_URL": "http://localhost:8080",
    }


def test_shell_text_in_a_value_stays_literal_and_never_runs(tmp_path: Path) -> None:
    files = {".env.data": "DATA_DIR=./d $(touch marker) &\\x\nPOSTGRES_DIR=${DATA_DIR}/postgres\n"}
    result, values = load_env(tmp_path, files, ["POSTGRES_DIR"])
    assert result.returncode == 0, result.stderr
    assert values["POSTGRES_DIR"] == "./d $(touch marker) &\\x/postgres"
    assert not (tmp_path / "marker").exists()


def test_a_reference_to_an_unset_key_fails_and_names_the_key(tmp_path: Path) -> None:
    files = {".env.data": "POSTGRES_DIR=${DATA_DIR}/postgres\n"}
    result, _ = load_env(tmp_path, files, ["POSTGRES_DIR"])
    assert result.returncode != 0
    assert "POSTGRES_DIR" in result.stderr and "DATA_DIR" in result.stderr


@pytest.mark.parametrize("body", ["DATA_DIR=${DATA_DIR}\n", "A_DIR=${B_DIR}\nB_DIR=${A_DIR}\n"])
def test_a_cycle_fails(tmp_path: Path, body: str) -> None:
    result, _ = load_env(tmp_path, {".env.data": body}, [])
    assert result.returncode != 0
    assert "cycle" in result.stderr


def test_an_indented_line_is_never_a_key(tmp_path: Path) -> None:
    body = "DATA_DIR=./data\n                 # a continuation comment\n  NOT_A_KEY=1\nLOGS_DIR=${DATA_DIR}/logs\n"
    (tmp_path / ".env.data.template").write_text(body)
    result, _ = load_env(tmp_path, {".env.data": body}, [])
    assert result.returncode == 0, result.stderr
    keys = subprocess.run(
        ["bash", "-c", f'source "{LIB}"; env_keys "$1" | paste -sd, -', "bash", str(tmp_path / ".env.data")],
        env={"PATH": os.environ["PATH"], "CTL_ROOT": str(tmp_path), "NO_COLOR": "1"},
        capture_output=True, text=True, check=False,
    )
    assert keys.stdout.strip() == "DATA_DIR,LOGS_DIR"
