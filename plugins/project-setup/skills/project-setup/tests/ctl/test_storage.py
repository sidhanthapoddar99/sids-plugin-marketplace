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


RESOLVE = ('source "$1"; cd "$CTL_ROOT"; require_env; resolve_storage_dirs; resolve_storage_dirs; '
           'bash -c \'printf "%s\\n" "$BASE_DIR" "$DATA_DIR" "$LOGS_DIR" "$BACKUP_DIR"\'')


def resolve(root, env_text, shell=None):
    """Load env_text as the root .env the way every ctl verb does, then resolve the storage paths."""
    root.mkdir(exist_ok=True)
    (root / ".env").write_text(env_text)
    env = {"PATH": os.environ["PATH"], "CTL_ROOT": str(root), "NO_COLOR": "1", **(shell or {})}
    result = subprocess.run(
        ["bash", "-euc", RESOLVE, "bash", str(TEMPLATE / "scripts/common/_lib.sh")],
        cwd=root.parent, env=env, text=True, capture_output=True, timeout=10,
    )
    return result, result.stdout.splitlines()


def shipped(base=None):
    """The shipped .env.template as a filled .env, with BASE_DIR replaced when base is given."""
    text = (TEMPLATE / ".env.template").read_text()
    assert "\nBASE_DIR=.\n" in text
    return text if base is None else text.replace("\nBASE_DIR=.\n", f"\nBASE_DIR={base}\n")


def test_the_shipped_block_derives_every_path_from_base_dir(tmp_path):
    root = tmp_path / "project space"
    result, paths = resolve(root, shipped())
    assert result.returncode == 0, result.stderr
    assert paths == [str(root), str(root / "data"), str(root / "logs"), str(root / "logs/backups")]


def test_an_absolute_base_dir_moves_every_path(tmp_path):
    root, deploy = tmp_path / "project", tmp_path / "deploy root/app"
    result, paths = resolve(root, shipped(deploy))
    assert result.returncode == 0, result.stderr
    assert paths == [str(deploy), str(deploy / "data"), str(deploy / "logs"), str(deploy / "logs/backups")]
    assert not deploy.exists() and not (root / "data").exists()


@pytest.mark.parametrize(("shell", "expected"), [
    ({"BASE_DIR": "/srv/app"}, ["/srv/app", "/srv/app/data", "/srv/app/logs", "/srv/app/logs/backups"]),
    ({"DATA_DIR": "/mnt/fast/data"}, ["{root}", "/mnt/fast/data", "{root}/logs", "{root}/logs/backups"]),
    ({"BASE_DIR": "/srv/app", "LOGS_DIR": "/var/log/app"},
     ["/srv/app", "/srv/app/data", "/var/log/app", "/var/log/app/backups"]),
], ids=["base", "data", "base-and-logs"])
def test_a_shell_value_wins_and_the_derived_paths_follow_it(tmp_path, shell, expected):
    root = tmp_path / "project"
    result, paths = resolve(root, shipped(), shell)
    assert result.returncode == 0, result.stderr
    assert paths == [path.format(root=root) for path in expected]


def test_a_relative_base_dir_resolves_against_each_checkout(tmp_path):
    for name in ("main", "slot-1"):
        root = tmp_path / name
        result, paths = resolve(root, shipped())
        assert result.returncode == 0, result.stderr
        assert paths[1:3] == [str(root / "data"), str(root / "logs")]
    result, paths = resolve(tmp_path / "main", shipped("./state"))
    assert result.returncode == 0, result.stderr
    assert paths == [str(tmp_path / "main/state"), str(tmp_path / "main/state/data"),
                     str(tmp_path / "main/state/logs"), str(tmp_path / "main/state/logs/backups")]


@pytest.mark.parametrize("base", ["./", "./state/.", "state//", "./state/./"])
def test_dot_segments_and_doubled_slashes_are_normalized(tmp_path, base):
    root = tmp_path / "project"
    result, paths = resolve(root, shipped(base))
    assert result.returncode == 0, result.stderr
    home = root if base == "./" else root / "state"
    assert paths == [str(home), str(home / "data"), str(home / "logs"), str(home / "logs/backups")]


def test_an_env_from_before_base_dir_keeps_its_paths(tmp_path):
    root = tmp_path / "project"
    result, paths = resolve(root, "DATA_DIR=./data\nLOGS_DIR=./logs\nBACKUP_DIR=${LOGS_DIR}/backups\n")
    assert result.returncode == 0, result.stderr
    assert paths == [str(root), str(root / "data"), str(root / "logs"), str(root / "logs/backups")]


@pytest.mark.parametrize("key", ["BASE_DIR", "DATA_DIR", "LOGS_DIR", "BACKUP_DIR"])
@pytest.mark.parametrize("value", ["", "   ", "${MISSING}/path", "../shared", "/srv/app/../other"])
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
