"""`ctl setup env`: the env step alone, shared with `ctl setup`, and nothing installed.

The tests run the real setup worker in synthetic repositories. Recording doubles stand in for mise,
the package managers and lefthook, so a call to any of them leaves a file behind.
"""

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from test_setup_runtime import ENV, TEMPLATE, fake_mise, fake_tool, manifest, scaffold

STORAGE = "BASE_DIR=.\nDATA_DIR=${BASE_DIR}/data\nLOGS_DIR=${BASE_DIR}/logs\nBACKUP_DIR=${LOGS_DIR}/backups\n"
CREDENTIALS = "JWT_SIGNING_KEY=\nPOSTGRES_PASSWORD=\nPROVIDER_API_KEY=\n"
ENTRY_POINTS = [pytest.param((), id="setup"), pytest.param(("env",), id="setup-env")]


def run(root: Path, *args: str, **overrides: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": str(root / "bin"), "HOME": str(root), "CTL_ROOT": str(root), "NO_COLOR": "1", **overrides}
    return subprocess.run(["/bin/bash", str(root / "scripts/config/setup.sh"), *args],
                          env=env, capture_output=True, text=True, check=False)


def record_everything(root: Path) -> None:
    """Resolved tool versions, one source manifest per ecosystem, hooks, and a recording double for each."""
    fake_mise(root)
    for tool in ("uv", "bun", "go", "lefthook"):
        fake_tool(root, tool)
    for path in ("api/pyproject.toml", "web/package.json", "cli/go.mod"):
        manifest(root, path)
    (root / "lefthook.yml").write_text("pre-commit: {}\n")
    (root / ".git").mkdir()


def values(root: Path) -> dict[str, str]:
    return dict(line.split("=", 1) for line in (root / ".env").read_text().splitlines() if "=" in line)


def test_setup_env_installs_nothing(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "JWT_SIGNING_KEY=\n")
    record_everything(tmp_path)
    result = run(tmp_path, "env")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not (tmp_path / "mise.calls").exists()
    assert not (tmp_path / "tool.calls").exists()
    assert re.fullmatch(r"[0-9a-f]{64}", values(tmp_path)["JWT_SIGNING_KEY"])
    assert (tmp_path / ".env").stat().st_mode & 0o777 == 0o600
    assert (tmp_path / "state/postgres").is_dir() and (tmp_path / "output/copies").is_dir()
    assert "installing" not in result.stdout
    # The same repository under full setup reaches every double, so silence above means nothing ran.
    result = run(tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / "mise.calls").read_text().splitlines()[0] == "install"
    tools = {line.split("|")[0] for line in (tmp_path / "tool.calls").read_text().splitlines()}
    assert {"uv", "bun", "go", "lefthook"} <= tools


def test_a_key_whose_comment_names_its_empty_default_gets_no_blank_warning(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "# cores the tests use\n# empty: every core\nTEST_CPUS=\n"
             "# Empty or 0: off\nWORKTREE_ONLY=\n\n# the address support mail goes to\nSUPPORT_EMAIL=\n")
    result = run(tmp_path, "env")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "blank setting: TEST_CPUS" not in result.stderr
    assert "blank setting: WORKTREE_ONLY" not in result.stderr
    assert "blank setting: SUPPORT_EMAIL" in result.stderr


def test_in_a_slot_setup_env_adds_no_port_number_and_changes_nothing(tmp_path: Path) -> None:
    slot = tmp_path / ".worktrees/slot-1"
    slot.mkdir(parents=True)
    scaffold(slot, ENV + "METRICS_PORT=9100\nMETRICS_URL=http://localhost:${METRICS_PORT}\n# BETA_PORT=9300\n")
    # A copy of the template would hold the main tree's ports, so a slot without .env gets none.
    result = run(slot, "env")
    assert result.returncode != 0
    assert "slot-1 has no .env" in result.stderr
    assert not (slot / ".env").exists()
    (slot / ".env").write_text(ENV)
    result = run(slot, "env")
    assert result.returncode != 0
    assert ".env lacks METRICS_PORT, a port .env.template declares. In slot-1" in result.stderr
    assert (slot / ".env").read_text() == ENV
    # With the port added by hand, at the slot's offset, the rest is added as in any checkout.
    (slot / ".env").write_text(ENV + "METRICS_PORT=9200\n")
    result = run(slot, "env")
    assert result.returncode == 0, result.stdout + result.stderr
    assert values(slot)["METRICS_PORT"] == "9200"
    assert values(slot)["METRICS_URL"] == "http://localhost:${METRICS_PORT}"


def test_the_template_names_the_empty_default_of_every_testing_and_worktree_key() -> None:
    blank = re.findall(r"^((?:TEST|WORKTREE)_[A-Z_]+)=$", (TEMPLATE / ".env.template").read_text(), re.M)
    script = 'source "$1"; blank_by_design_keys "$2"'
    listed = subprocess.run(["bash", "-c", script, "bash", str(TEMPLATE / "scripts/config/_credentials.sh"),
                             str(TEMPLATE / ".env.template")], capture_output=True, text=True, check=True).stdout.split()
    assert blank and set(blank) <= set(listed), set(blank) - set(listed)


def test_setup_env_runs_before_the_versions_are_resolved(tmp_path: Path) -> None:
    scaffold(tmp_path)
    (tmp_path / ".mise.toml").write_text('[tools]\nbun = "<version>"\n')
    manifest(tmp_path, "web/package.json", '{"devDependencies": {"vite": "<version>"}}')
    assert run(tmp_path, "env").returncode == 0
    result = run(tmp_path)
    assert result.returncode != 0
    assert "toolchains were not installed" in result.stderr


def test_both_entry_points_run_one_env_step(tmp_path: Path) -> None:
    """setup env's output is the head of setup's output, and both leave the same .env and dirs."""
    roots = {name: tmp_path / name for name in ("setup", "setup-env")}
    output, files = {}, {}
    for name, root in roots.items():
        root.mkdir()
        scaffold(root, STORAGE + CREDENTIALS)
        result = run(root, *(("env",) if name == "setup-env" else ()), PROVIDER_API_KEY="supplied")
        assert result.returncode == 0, result.stdout + result.stderr
        assert "supplied" not in result.stdout + result.stderr
        output[name] = result.stdout.replace(str(root), "<root>").splitlines()
        files[name] = values(root)
        dirs = sorted(str(path.relative_to(root)) for top in ("data", "logs") for path in (root / top).rglob("*"))
        assert dirs == ["data/neo4j", "data/postgres", "data/redis",
                        "logs/backups", "logs/dev", "logs/run", "logs/test_build"]
    *env_step, last = output["setup-env"]
    assert last.startswith("next: ctl setup installs")
    assert output["setup"][:len(env_step) + 1] == env_step + ["▸ installing toolchains + dependencies"]
    assert files["setup"].keys() == files["setup-env"].keys()
    for name in roots:
        assert files[name]["PROVIDER_API_KEY"] == ""
        assert re.fullmatch(r"[0-9a-f]{64}", files[name]["JWT_SIGNING_KEY"])
        assert re.fullmatch(r"[A-Za-z0-9]{24}", files[name]["POSTGRES_PASSWORD"])
    for key in ("BASE_DIR", "DATA_DIR", "LOGS_DIR", "BACKUP_DIR"):
        assert files["setup"][key] == files["setup-env"][key]


@pytest.mark.parametrize("args", ENTRY_POINTS)
def test_rerun_keeps_every_value_and_appends_the_keys_the_template_gained(tmp_path: Path, args: tuple[str, ...]) -> None:
    scaffold(tmp_path, STORAGE + CREDENTIALS)
    assert run(tmp_path, *args, PROVIDER_API_KEY="supplied").returncode == 0
    edited = (tmp_path / ".env").read_text().replace("BASE_DIR=.", "BASE_DIR=./state")
    (tmp_path / ".env").write_text(edited)
    with (tmp_path / ".env.template").open("a") as handle:
        handle.write("NEW_FLAG=0\n")
    result = run(tmp_path, *args, PROVIDER_API_KEY="supplied")
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / ".env").read_text() == edited + "NEW_FLAG=0\n"
    assert (tmp_path / "state/data/postgres").is_dir()


@pytest.mark.parametrize("args", ENTRY_POINTS)
def test_an_env_step_failure_stops_before_any_install(tmp_path: Path, args: tuple[str, ...]) -> None:
    scaffold(tmp_path, STORAGE + CREDENTIALS)
    (tmp_path / "scripts/config/required-credentials.conf").write_text("PROVIDER_API_KEY\n")
    record_everything(tmp_path)
    result = run(tmp_path, *args)
    assert result.returncode != 0
    assert "required supplied credential is blank: PROVIDER_API_KEY" in result.stderr
    assert not (tmp_path / "mise.calls").exists() and not (tmp_path / "tool.calls").exists()
    assert not (tmp_path / "data").exists()


@pytest.mark.parametrize(("base", "shell"), [("/abs", None), (".", "/abs")], ids=["in-env", "in-shell"])
def test_setup_env_creates_the_storage_dirs_under_an_absolute_base_dir(
    tmp_path: Path, base: str, shell: str | None
) -> None:
    root, deploy = tmp_path / "repo", tmp_path / "deploy root"
    root.mkdir()
    scaffold(root, STORAGE.replace("BASE_DIR=.", f"BASE_DIR={deploy if base == '/abs' else base}"))
    overrides = {"BASE_DIR": str(deploy)} if shell else {}
    result = run(root, "env", **overrides)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (deploy / "data/postgres").is_dir() and (deploy / "logs/backups").is_dir()
    assert not (root / "data").exists() and not (root / "logs").exists()
    assert f"data {deploy}/data" in result.stdout


def router(root: Path) -> Path:
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    shutil.copy(TEMPLATE / "ctl", root / "ctl")
    return root / "ctl"


@pytest.mark.parametrize("args", [(), ("--help",), ("help",)], ids=["bare", "--help", "help"])
def test_ctl_help_lists_setup_env(tmp_path: Path, args: tuple[str, ...]) -> None:
    ctl = router(tmp_path)
    result = subprocess.run(["bash", str(ctl), *args], env={"PATH": os.environ["PATH"], "NO_COLOR": "1"},
                            capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert re.search(r"^  setup env +\S", result.stdout, re.MULTILINE)
    assert re.search(r"^  setup +\S", result.stdout, re.MULTILINE)


@pytest.mark.parametrize(("args", "code", "text"), [
    (("setup", "--help"), 0, "env             the environment only"),
    (("setup", "env", "--help"), 0, "ctl setup env — Set up the environment only"),
    (("setup", "env", "-h"), 0, "Installs no toolchain and no dependency"),
    (("setup", "env", "extra"), 1, "usage: ctl setup env [-h]"),
    (("setup", "extra"), 1, "usage: ctl setup [env] [-h]"),
])
def test_setup_help_and_usage_have_no_side_effects(tmp_path: Path, args: tuple[str, ...], code: int, text: str) -> None:
    ctl = router(tmp_path)
    shutil.copy(TEMPLATE / ".env.template", tmp_path)
    result = subprocess.run(["bash", str(ctl), *args], env={"PATH": os.environ["PATH"], "NO_COLOR": "1"},
                            capture_output=True, text=True, check=False)
    assert result.returncode == code, result.stdout + result.stderr
    assert text in result.stdout + result.stderr
    assert not (tmp_path / ".env").exists() and not (tmp_path / "data").exists()

