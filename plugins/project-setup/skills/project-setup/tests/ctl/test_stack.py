"""ctl stack discovery: configs and modifiers by filename, presets by line.

The suite runs the real shell library (scripts/common/_lib.sh) in a scratch root, so it proves the
discovery itself and not a copy of it. A config is docker/compose.<name>.yaml with no dot in the
name; a modifier is docker/compose.m.<name>.yaml; a preset is one `<name>: "<args>"` line in
docker/presets.yaml, and its value is fed back to the `ctl up` parser as it is.
"""

import os
import subprocess
from pathlib import Path

LIB = Path(__file__).resolve().parents[2] / "template/scripts/common/_lib.sh"


def run_lib(root: Path, body: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", str(root)), "NO_COLOR": "1"}
    env["CTL_ROOT"] = str(root)
    script = f'source "$1"; cd "$CTL_ROOT"; {body}'
    return subprocess.run(
        ["bash", "-c", script, "bash", str(LIB)], env=env, capture_output=True, text=True, check=False
    )


def scaffold(root: Path, files: dict[str, str]) -> None:
    (root / "docker").mkdir(exist_ok=True)
    for name, body in files.items():
        (root / "docker" / name).write_text(body)


def test_configs_are_the_dotless_names_and_modifiers_the_m_names(tmp_path: Path) -> None:
    scaffold(
        tmp_path,
        {
            "compose.base.yaml": "services: {}\n",
            "compose.db.yaml": "services: {}\n",
            "compose.m.expose.yaml": "services: {}\n",
            "compose.m.expose_db.yaml": "services: {}\n",
            "presets.yaml": "",
        },
    )
    result = run_lib(tmp_path, "list_configs | paste -sd, -; list_modifiers | paste -sd, -")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["base,db", "expose,expose_db"]


def test_compose_files_is_the_config_then_each_modifier(tmp_path: Path) -> None:
    scaffold(tmp_path, {})
    result = run_lib(tmp_path, "compose_files db expose_db public | paste -sd' ' -")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == (
        "docker/compose.db.yaml docker/compose.m.expose_db.yaml docker/compose.m.public.yaml"
    )


PRESETS = """\
# a comment
dev: "--config db +expose_db"
local:   --config base +expose_web   # trailing comment
bad line without a colon
"""


def test_presets_list_names_and_return_the_bare_argument_line(tmp_path: Path) -> None:
    scaffold(tmp_path, {"presets.yaml": PRESETS})
    result = run_lib(
        tmp_path,
        'list_presets | paste -sd, -; preset_args dev; preset_args local; '
        'preset_args nope && echo found || echo absent',
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "dev,local",
        "--config db +expose_db",
        "--config base +expose_web",
        "absent",
    ]


def test_no_presets_file_means_no_presets(tmp_path: Path) -> None:
    scaffold(tmp_path, {})
    result = run_lib(tmp_path, "list_presets | wc -l; preset_args x && echo found || echo absent")
    assert result.returncode == 0, result.stderr
    assert result.stdout.split() == ["0", "absent"]


QUIRKS = """\
q: "--config db # kept"
s: '--config base +expose'
u: --config dev   # dropped
c: # nothing
n:"--config db"
"""


def test_preset_value_quoting(tmp_path: Path) -> None:
    scaffold(tmp_path, {"presets.yaml": QUIRKS})
    result = run_lib(tmp_path, "for p in q s u c n; do preset_args $p; done")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "--config db # kept",
        "--config base +expose",
        "--config dev",
        "",
        "--config db",
    ]


UP = Path(__file__).resolve().parents[2] / "template/scripts/container/up.sh"
DEV = Path(__file__).resolve().parents[2] / "template/scripts/dev/dev.sh"


def run_worker(root: Path, worker: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run a ctl worker in a scratch root. Every path exercised here exits before docker is needed."""
    (root / "scripts").mkdir(exist_ok=True)
    common = root / "scripts" / "common"
    if not common.exists():
        common.symlink_to(LIB.parent, target_is_directory=True)
    env = {"PATH": os.environ["PATH"], "HOME": str(root), "NO_COLOR": "1", "CTL_ROOT": str(root)}
    return subprocess.run(
        ["bash", str(worker), *args], env=env, capture_output=True, text=True, check=False
    )


def test_duplicate_names_read_first_and_list_once(tmp_path: Path) -> None:
    scaffold(tmp_path, {"presets.yaml": 'dup: "--config db"\ndup: "--config base"\n'})
    result = run_lib(tmp_path, "list_presets | paste -sd, -; preset_args dup")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["dup", "--config db"]


def test_crlf_lines_are_read_like_lf_lines(tmp_path: Path) -> None:
    scaffold(tmp_path, {"presets.yaml": 'dev: "--config db +expose_db"\r\nlocal: --config base\r\n'})
    result = run_lib(tmp_path, "preset_args dev; preset_args local")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["--config db +expose_db", "--config base"]


def test_a_stored_run_flag_is_refused_by_name(tmp_path: Path) -> None:
    scaffold(tmp_path, {"compose.base.yaml": "services: {}\n", "presets.yaml": 'withy: "--config base -y"\n'})
    result = run_worker(tmp_path, UP, "preset", "withy", "--dry-run")
    assert result.returncode != 0
    assert "withy" in result.stderr and "'-y'" in result.stderr


def test_an_empty_preset_is_an_error_not_the_default(tmp_path: Path) -> None:
    scaffold(tmp_path, {"compose.base.yaml": "services: {}\n", "presets.yaml": "empty:\n"})
    result = run_worker(tmp_path, UP, "preset", "empty", "--dry-run")
    assert result.returncode != 0
    assert "empty" in result.stderr


def test_a_shape_flag_beside_a_preset_name_is_refused(tmp_path: Path) -> None:
    scaffold(tmp_path, {"compose.base.yaml": "services: {}\n", "presets.yaml": 'dev: "--config db"\n'})
    result = run_worker(tmp_path, UP, "preset", "dev", "--services", "postgres", "--dry-run")
    assert result.returncode != 0
    assert "set-preset dev" in result.stderr


def test_ctl_dev_names_a_missing_dev_preset(tmp_path: Path) -> None:
    scaffold(tmp_path, {"presets.yaml": 'local: "--config base"\n'})
    for name in (".env.secrets", ".env.data", ".env.proxy"):
        (tmp_path / name).write_text("API_PORT=8000\nAPI_HOST=localhost\n")
    result = run_worker(tmp_path, DEV, "api", "--dry-run")
    assert result.returncode == 0, result.stderr
    assert "preset 'dev' missing" in result.stdout
