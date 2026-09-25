"""Rust dev cleanup removes only generated project debug output and managed logs."""

import os
import shutil
import subprocess
from pathlib import Path


TEMPLATE = Path(__file__).resolve().parents[2] / "template"


def project(tmp_path: Path) -> tuple[Path, Path]:
    root = tmp_path / "project space"
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    shutil.copy(TEMPLATE / "ctl", root / "ctl")
    logs = tmp_path / "custom logs"
    (root / ".env").write_text(f"LOGS_DIR={logs}\n")
    (root / "apps/engine").mkdir(parents=True)
    (root / "apps/engine/Cargo.toml").write_text("[package]\nname = 'engine'\n")
    return root, logs


def ctl(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": os.environ["PATH"], "HOME": str(root), "NO_COLOR": "1"}
    return subprocess.run(["bash", str(root / "ctl"), *args], env=env,
                          capture_output=True, text=True, check=False)


def test_dev_clean_scopes_debug_builds_and_rust_logs(tmp_path: Path) -> None:
    root, logs = project(tmp_path)
    debug = root / "apps/engine/target/debug"
    (debug / "incremental").mkdir(parents=True)
    (debug / "incremental/cache").write_text("generated")
    release = root / "apps/engine/target/release/binary"
    release.parent.mkdir(parents=True)
    release.write_text("keep")
    (root / "apps/engine/Cargo.lock").write_text("keep")
    (root / "data").mkdir()
    (root / "data/user-file").write_text("keep")
    (logs / "dev").mkdir(parents=True)
    for name in ("dev-engine.log", "controller-engine.log", "dev-api.log"):
        (logs / "dev" / name).write_text("log")
    outside = tmp_path / "global cargo cache"
    outside.mkdir()
    (outside / "cache").write_text("keep")

    preview = ctl(root, "clean", "rust", "--dry-run")
    assert preview.returncode == 0, preview.stderr
    assert str(debug) in preview.stdout
    assert "dev-engine.log" in preview.stdout and "controller-engine.log" in preview.stdout
    assert "dev-api.log" not in preview.stdout
    assert debug.is_dir() and (logs / "dev/dev-engine.log").exists()

    result = ctl(root, "clean", "rust")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not debug.exists()
    assert not (logs / "dev/dev-engine.log").exists()
    assert not (logs / "dev/controller-engine.log").exists()
    assert release.read_text() == "keep"
    assert (root / "apps/engine/Cargo.lock").read_text() == "keep"
    assert (root / "data/user-file").read_text() == "keep"
    assert (logs / "dev/dev-api.log").read_text() == "log"
    assert (outside / "cache").read_text() == "keep"
    assert ctl(root, "clean", "rust").returncode == 0


def test_clean_help_distinguishes_full_and_rust_cleanup(tmp_path: Path) -> None:
    root, _ = project(tmp_path)
    full = ctl(root, "clean", "--help")
    rust = ctl(root, "clean", "rust", "--help")
    assert full.returncode == rust.returncode == 0
    assert "teardown" not in rust.stdout.lower()
    assert "target/debug" in rust.stdout
    assert "ctl clean rust" in full.stdout


def test_dev_clean_refuses_recorded_rust_process(tmp_path: Path) -> None:
    root, logs = project(tmp_path)
    debug = root / "apps/engine/target/debug"
    debug.mkdir(parents=True)
    (logs / "run/dev-engine.process").mkdir(parents=True)

    result = ctl(root, "clean", "rust")
    assert result.returncode != 0
    assert "stop the Rust dev process" in result.stderr
    assert debug.is_dir()


def test_dev_clean_refuses_symlinked_build_output(tmp_path: Path) -> None:
    root, logs = project(tmp_path)
    outside = tmp_path / "other build"
    outside.mkdir()
    (outside / "keep").write_text("keep")
    (root / "apps/engine/target").symlink_to(outside, target_is_directory=True)
    (logs / "dev").mkdir(parents=True)
    (logs / "dev/dev-engine.log").write_text("keep")

    result = ctl(root, "clean", "rust")
    assert result.returncode != 0
    assert "is a symlink" in result.stderr
    assert (outside / "keep").read_text() == "keep"
    assert (logs / "dev/dev-engine.log").read_text() == "keep"


def test_dev_clean_refuses_symlinked_log(tmp_path: Path) -> None:
    root, logs = project(tmp_path)
    debug = root / "apps/engine/target/debug"
    debug.mkdir(parents=True)
    outside = tmp_path / "other log"
    outside.write_text("keep")
    (logs / "dev").mkdir(parents=True)
    (logs / "dev/dev-engine.log").symlink_to(outside)

    result = ctl(root, "clean", "rust")
    assert result.returncode != 0
    assert "is a symlink" in result.stderr
    assert debug.is_dir()
    assert outside.read_text() == "keep"
