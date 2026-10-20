"""Copy the template, never rebuild it: the copy script, the template core check and the tool hints."""

import os
import subprocess
from pathlib import Path

import pytest

from test_setup_runtime import executable, fake_mise, scaffold

SKILL = Path(__file__).resolve().parents[2]
TEMPLATE = SKILL / "template"
TEMPLATE_SH = SKILL / "scripts/template.sh"
MANIFEST_SH = Path(__file__).with_name("template_core_manifest.sh")
CORE = TEMPLATE / "scripts/common/_template-core.sh"
EXCEPTION = "- `template-core scripts/common/_compose_start.sh`: the start helper waits longer for a slow engine.\n"


def bash(*args: object, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", *map(str, args)], capture_output=True, text=True, check=False, env=env)


def copied(root: Path) -> Path:
    root.mkdir(exist_ok=True)
    result = bash(TEMPLATE_SH, "copy", root)
    assert result.returncode == 0, result.stderr
    return root


def core_problems(root: Path) -> subprocess.CompletedProcess[str]:
    return bash("-c", 'source "$1" && template_core_problems "$2"', "_", CORE, root)


def run_check(root: Path) -> subprocess.CompletedProcess[str]:
    env = {"PATH": os.environ["PATH"], "HOME": str(root), "NO_COLOR": "1"}
    return bash(root / "scripts/config/check.sh", env=env)


def edit(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    assert old in text, f"{old!r} not in {path}"
    path.write_text(text.replace(old, new, 1))


def files(root: Path) -> set[str]:
    return {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file() or path.is_symlink()}


def test_shipped_manifest_matches_the_helpers() -> None:
    result = bash(MANIFEST_SH)
    assert result.returncode == 0, result.stderr
    shipped = (TEMPLATE / "scripts/common/template-core.sha256").read_text()
    assert result.stdout == shipped, "a shared helper changed: run bash tests/ctl/template_core_manifest.sh --write"


def test_copy_writes_the_whole_template_and_verify_is_green(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    assert files(root) == files(TEMPLATE)
    assert os.access(root / "ctl", os.X_OK)
    result = bash(TEMPLATE_SH, "verify", root)
    assert result.returncode == 0, result.stdout
    assert result.stdout.startswith("verdict: green")


def test_copy_refuses_to_overwrite_and_writes_nothing(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("the owner's readme\n")
    result = bash(TEMPLATE_SH, "copy", tmp_path)
    assert result.returncode == 1
    assert "  README.md" in result.stderr
    assert not (tmp_path / "ctl").exists()
    assert (tmp_path / "README.md").read_text() == "the owner's readme\n"


@pytest.mark.parametrize("existing", ["ctl", "scripts"])
def test_copy_sends_a_repo_with_its_own_router_to_staging(tmp_path: Path, existing: str) -> None:
    (tmp_path / existing).mkdir()
    result = bash(TEMPLATE_SH, "copy", tmp_path)
    assert result.returncode == 1
    assert "staging folder" in result.stderr
    assert not (tmp_path / ".mise.toml").exists()


def test_verify_fails_a_rebuilt_ctl(tmp_path: Path) -> None:
    executable(tmp_path / "ctl", 'exec "$(dirname "$0")/scripts/ctl.sh" "$@"\n')
    executable(tmp_path / "scripts/ctl.sh", 'case "${1:-}" in gate) for r in lint test; do "$0" "$r"; done ;; esac\n')
    result = bash(TEMPLATE_SH, "verify", tmp_path)
    assert result.returncode == 1
    first, summary = result.stdout.splitlines()[:2]
    assert first.startswith("verdict: red — not from the template (ctl does not source scripts/common/_lib.sh)")
    assert "files added" in summary


def test_verify_fails_a_copy_whose_helpers_were_rewritten(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    (root / "scripts/common/_lib.sh").write_text('#!/usr/bin/env bash\nload_env_file() { set -a; source "$1"; set +a; }\n')
    (root / "scripts/common/_process.sh").unlink()
    result = bash(TEMPLATE_SH, "verify", root)
    assert result.returncode == 1
    assert "helpers were changed" in result.stdout.splitlines()[0]
    assert "FAIL  scripts/common/_lib.sh differs from the template" in result.stdout
    assert "FAIL  scripts/common/_process.sh is missing" in result.stdout
    assert "removed  scripts/common/_process.sh" in result.stdout


def test_adapt_knobs_pass_and_any_other_edit_fails(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    lib = root / "scripts/common/_lib.sh"
    edit(lib, "DATA_SVCS-postgres redis neo4j}", "DATA_SVCS-postgres}")
    edit(lib, "SCHEMA_SVCS-migrate neo4j-init}", "SCHEMA_SVCS-migrate}")
    edit(lib, '[expose_db]="POSTGRES_PORT REDIS_PORT NEO4J_BOLT_PORT"', '[expose_db]="POSTGRES_PORT"')
    edit(lib, "PORT_PRESETS:-5380 5381 5382 4173", "PORT_PRESETS:-5380")
    assert core_problems(root).returncode == 0, core_problems(root).stdout
    edit(lib, "load_env_files() {", "load_env_files() { : ;")
    result = core_problems(root)
    assert result.returncode == 1
    assert result.stdout.startswith("scripts/common/_lib.sh differs")


def test_ctl_check_fails_a_helper_that_works_around_jq(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    result = run_check(root)
    assert "✓ scripts/common/ matches the template outside its [ADAPT] blocks" in result.stdout
    edit(root / "scripts/common/_compose_start.sh", "require_tools jq timeout", "require_tools timeout")
    result = run_check(root)
    assert result.returncode != 0
    assert "scripts/common/_compose_start.sh differs from the template" in result.stderr
    assert "matches the template outside" not in result.stdout


def test_ctl_check_fails_when_the_core_check_itself_is_gone(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    (root / "scripts/common/_template-core.sh").unlink()
    result = run_check(root)
    assert result.returncode != 0
    assert "scripts/common/_template-core.sh is missing" in result.stderr


def test_recorded_exception_counts_only_under_its_heading(tmp_path: Path) -> None:
    root = copied(tmp_path / "repo")
    edit(root / "scripts/common/_compose_start.sh", "require_tools jq timeout", "require_tools jq timeout sleep")
    agents = root / "AGENTS.md"
    agents.write_text("# brief\n\n## Exceptions to the standard layout\n\n" + EXCEPTION + "\n## Stack\n")
    assert core_problems(root).returncode == 0, core_problems(root).stdout
    agents.write_text("# brief\n\n## Stack\n\n" + EXCEPTION)
    assert core_problems(root).returncode == 1
    result = bash(TEMPLATE_SH, "verify", root)
    assert "scripts/common/_compose_start.sh differs" in result.stdout


@pytest.mark.parametrize("own_manifest", ["deleted", "regenerated"])
def test_verify_names_a_copy_of_another_template_version(tmp_path: Path, own_manifest: str) -> None:
    root = copied(tmp_path / "repo")
    edit(root / "scripts/common/_paths.sh", "\n", "\n# an older revision of this helper\n")
    manifest = root / "scripts/common/template-core.sha256"
    if own_manifest == "deleted":
        manifest.unlink()
        expected = "a template copy older than template-core.sha256"
    else:
        digest = bash("-c", 'source "$1" && template_core_digest "$2"', "_", CORE, root / "scripts/common/_paths.sh")
        lines = [f"{digest.stdout.strip()}  scripts/common/_paths.sh" if line.endswith("/_paths.sh") else line
                 for line in manifest.read_text().splitlines()]
        manifest.write_text("\n".join(lines) + "\n")
        expected = "a copy of another template version"
    result = bash(TEMPLATE_SH, "verify", root)
    assert result.returncode == 1
    assert expected in result.stdout.splitlines()[0]


def test_digest_masks_only_adapt_blocks(tmp_path: Path) -> None:
    base = "a=1\n# [ADAPT] the knob\n# what it does\nKNOB=one\nOTHER=two\n# a later comment\nb=2\n\nc=3\n"
    variants = {
        "knob value": (base.replace("KNOB=one", "KNOB=three"), True),
        "second knob line": (base.replace("OTHER=two", "OTHER=four"), True),
        "knob comment": (base.replace("what it does", "what it sets"), True),
        "comment after the knob": (base.replace("a later comment", "a changed comment"), False),
        "code after the comment": (base.replace("b=2", "b=5"), False),
        "code before the block": (base.replace("a=1", "a=9"), False),
    }
    (tmp_path / "base").write_text(base)
    digest = lambda name: bash("-c", 'source "$1" && template_core_digest "$2"', "_", CORE, tmp_path / name).stdout
    for name, (text, same) in variants.items():
        (tmp_path / name).write_text(text)
        assert (digest(name) == digest("base")) is same, name


@pytest.mark.parametrize(
    ("declaration", "tool", "hint"),
    [
        ('jq = "<version>"\n', "jq", "jq is declared in .mise.toml as '<version>': resolve the version with the user"),
        ('jq = "1.8.1"   # ctl itself\n', "jq", "jq is declared in .mise.toml: run ctl setup to install it"),
        ('bun = "1.0.0"\n', "jq", "declare jq in .mise.toml and run ctl setup"),
        ('rust = "stable"\n', "cargo", "rust is declared in .mise.toml: run ctl setup"),
    ],
)
def test_missing_tool_names_its_install_step(tmp_path: Path, declaration: str, tool: str, hint: str) -> None:
    scaffold(tmp_path)
    fake_mise(tmp_path)
    (tmp_path / ".mise.toml").write_text("[tools]\n" + declaration)
    result = bash("-euc", f'source "$CTL_ROOT/scripts/common/_lib.sh"; require_tools {tool}',
                  env={"CTL_ROOT": str(tmp_path), "PATH": str(tmp_path / "bin"), "NO_COLOR": "1"})
    assert result.returncode == 1
    assert f"required tool missing on PATH: {tool} — {hint}" in result.stderr
    assert "do not code around it" in result.stderr


def test_shim_that_cannot_run_is_named(tmp_path: Path) -> None:
    scaffold(tmp_path)
    fake_mise(tmp_path)
    executable(tmp_path / "mise/shims/jq", "exit 1\n")
    result = bash("-euc", 'source "$CTL_ROOT/scripts/common/_lib.sh"; require_tools jq',
                  env={"CTL_ROOT": str(tmp_path), "PATH": f"{tmp_path / 'bin'}:{tmp_path / 'mise/shims'}", "NO_COLOR": "1"})
    assert result.returncode == 1
    assert "required tool cannot run: jq" in result.stderr
    assert "a mise shim with no version selected for this repo" in result.stderr


def test_missing_mise_names_the_install_command(tmp_path: Path) -> None:
    scaffold(tmp_path)
    (tmp_path / ".mise.toml").write_text('[tools]\njq = "1.8.1"\n')
    result = bash("-euc", 'source "$CTL_ROOT/scripts/common/_lib.sh"; require_tools jq',
                  env={"CTL_ROOT": str(tmp_path), "PATH": str(tmp_path / "bin"), "NO_COLOR": "1"})
    assert result.returncode == 1
    assert "mise is required" in result.stderr
    assert "curl https://mise.run | sh" in result.stderr
