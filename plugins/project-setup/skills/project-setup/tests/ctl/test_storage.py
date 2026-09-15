import os
import shutil
import subprocess
from pathlib import Path

import pytest


TEMPLATE = Path(__file__).resolve().parents[2] / "template"


@pytest.mark.parametrize("custom", [False, True])
def test_storage_anchors_and_exports(tmp_path, custom):
    root = tmp_path / "project space"
    root.mkdir()
    external = tmp_path / "external logs"
    (root / ".env").write_text(
        "DATA_DIR=local data\nLOGS_DIR=file logs\nBACKUP_DIR=${LOGS_DIR}/backups\n"
        if custom else ""
    )
    env = {"PATH": os.environ["PATH"], "CTL_ROOT": str(root)}
    if custom:
        env["LOGS_DIR"] = str(external)
    result = subprocess.run(
        ["bash", "-euc", 'source "$1"; source "$2"; cd "$CTL_ROOT"; require_env; '
         'resolve_storage_dirs; resolve_storage_dirs; '
         'bash -c \'printf "%s\\n" "$DATA_DIR" "$LOGS_DIR" "$BACKUP_DIR"\'',
         "bash", str(TEMPLATE / "scripts/common/_lib.sh"),
         str(TEMPLATE / "scripts/common/_paths.sh")],
        cwd=tmp_path, env=env, text=True, capture_output=True, timeout=10,
    )
    assert result.returncode == 0, result.stderr
    logs = external if custom else root / "logs"
    assert result.stdout.splitlines() == [
        str(root / ("local data" if custom else "data")),
        str(logs), str(logs / "backups"),
    ]
    assert not (root / "logs").exists()
    assert not (root / "data").exists()


@pytest.mark.parametrize("key", ["DATA_DIR", "LOGS_DIR", "BACKUP_DIR"])
@pytest.mark.parametrize("value", ["", "   ", "${MISSING}/path"])
def test_invalid_storage_fails(tmp_path, key, value):
    result = subprocess.run(
        ["bash", "-euc", 'source "$1"; resolve_storage_dirs', "bash",
         str(TEMPLATE / "scripts/common/_paths.sh")],
        env={"PATH": os.environ["PATH"], "CTL_ROOT": str(tmp_path), key: value},
        capture_output=True, text=True, timeout=5,
    )
    assert result.returncode != 0
    assert key in result.stderr


def test_frozen_list_uses_custom_logs(tmp_path):
    root = tmp_path / "project"
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    library = root / "scripts/common/_lib.sh"
    with library.open("a") as stream:
        stream.write('\nsource "$CTL_ROOT/scripts/common/_paths.sh"\n')
    logs = tmp_path / "external logs"
    snapshot = logs / "test_build/build-example"
    snapshot.mkdir(parents=True)
    (snapshot / ".build-meta").write_text("name: sample\nbranch: main\ncommit: abc123\n")
    (root / ".env").write_text(f"LOGS_DIR={logs}\nDATA_DIR=custom data\n")
    result = subprocess.run(
        ["bash", str(root / "scripts/test/build.sh"), "start", "--list"],
        cwd=tmp_path, env={"PATH": os.environ["PATH"], "CTL_ROOT": str(root)},
        text=True, capture_output=True, timeout=5,
    )
    assert result.returncode == 0, result.stderr
    assert "build-example" in result.stdout
    assert not (root / "logs").exists()
