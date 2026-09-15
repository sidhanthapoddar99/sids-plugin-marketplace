"""Setup integration in synthetic repositories with isolated executable tool doubles."""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
ENV = "DATA_DIR=./state\nLOGS_DIR=./output\nBACKUP_DIR=${LOGS_DIR}/copies\n"
PRUNED = (
    "node_modules", "target", ".venv", "venv", "build", "dist", "vendor", ".git",
    ".hg", ".svn", ".cache", "__pycache__", ".next", ".nuxt", ".output", "coverage", ".tox",
    "third_party", "third-party", "generated", ".generated",
)


def executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/bash\nset -eu\n" + body)
    path.chmod(0o755)


def scaffold(root: Path, env: str = ENV) -> None:
    shutil.copytree(TEMPLATE / "scripts", root / "scripts")
    (root / ".env.template").write_text(env)
    (root / "bin").mkdir()
    for name in ("bash", "dirname", "find", "grep", "cp", "chmod", "tail", "mktemp", "mv", "rm", "mkdir", "openssl"):
        (root / "bin" / name).symlink_to(shutil.which(name))


def run_setup(root: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": str(root / "bin"), "HOME": str(root), "CTL_ROOT": str(root), "NO_COLOR": "1"}
    env.update(overrides)
    return subprocess.run(
        ["/bin/bash", str(root / "scripts/config/setup.sh")],
        env=env, capture_output=True, text=True, check=False,
    )


def manifest(root: Path, name: str, body: str = "") -> None:
    path = root / "apps" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)


def fake_mise(root: Path, install: str = ":", activation: str | None = None) -> None:
    (root / ".mise.toml").write_text('[tools]\nbun = "1.0.0"\n')
    if activation is None:
        activation = 'printf \'export PATH="%s/tools:$PATH"\\n\' "$CTL_ROOT"'
    executable(root / "bin/mise", f'printf "%s\\n" "$*" >> "$CTL_ROOT/mise.calls"\n'
               f'case "$1" in install) {install} ;; env) {activation} ;; *) exit 9 ;; esac\n')


def fake_tool(root: Path, name: str, failure: str = "", location: str = "tools") -> None:
    executable(root / location / name,
               'printf "%s|%s|%s\\n" "${0##*/}" "$PWD" "$*" >> "$CTL_ROOT/tool.calls"\n'
               + failure + "\n")


def test_setup_activates_mise_then_installs_nested_sources(tmp_path: Path) -> None:
    scaffold(tmp_path)
    fake_mise(tmp_path)
    for tool in ("uv", "bun", "go"):
        fake_tool(tmp_path, tool)
    sources = {"suite/nested/api/pyproject.toml": "uv", "packages/ui/widgets/package.json": "bun",
               "suite/cli/go.mod": "go"}
    for path in sources:
        manifest(tmp_path, path)
    for directory in PRUNED:
        for name in ("pyproject.toml", "package.json", "go.mod", "Cargo.toml", "rust-toolchain.toml"):
            manifest(tmp_path, f"suite/{directory}/decoy/{name}", "<version>")
    manifest(tmp_path, "/".join(["deep"] * 13) + "/package.json", "<version>")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "package.json").write_text("<version>")
    (tmp_path / "apps/linked").symlink_to(outside, target_is_directory=True)
    result = run_setup(tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / "mise.calls").read_text().splitlines() == ["install", "env -s bash"]
    calls = (tmp_path / "tool.calls").read_text().splitlines()
    for path, tool in sources.items():
        directory = tmp_path / "apps" / Path(path).parent
        command = {"uv": "sync", "bun": "install", "go": "mod download"}[tool]
        assert f"{tool}|{directory}|{command}" in calls
    assert len(calls) == 6
    assert (tmp_path / "state/postgres").is_dir()
    assert (tmp_path / "output/copies").is_dir()
    assert not (tmp_path / "data").exists()
    assert not (tmp_path / "logs").exists()


@pytest.mark.parametrize(("install", "activation", "message"), [
    ("exit 7", None, "mise install failed"),
    (":", "exit 8", "mise activation failed"),
    (":", "printf 'false\\n'", "mise activation failed"),
    (":", ":", "no environment"),
])
def test_mise_failures_stop_setup(tmp_path: Path, install: str, activation: str | None, message: str) -> None:
    scaffold(tmp_path)
    fake_mise(tmp_path, install, activation)
    manifest(tmp_path, "web/package.json")
    fake_tool(tmp_path, "bun")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert message in result.stderr
    assert "next:" not in result.stdout
    assert not (tmp_path / "tool.calls").exists()


@pytest.mark.parametrize(("name", "filename", "failure"), [
    ("bun", "package.json", '[[ "$1" == --version ]]'),
    ("uv", "pyproject.toml", '[[ "$1" == --version ]]'),
    ("go", "go.mod", '[[ "$1" == version ]]'),
    ("bun", "package.json", "exit 5"),
])
def test_required_tool_and_dependency_failures(tmp_path: Path, name: str, filename: str, failure: str) -> None:
    scaffold(tmp_path)
    manifest(tmp_path, f"nested/app/{filename}")
    fake_tool(tmp_path, name, failure, "bin")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert name in result.stderr
    assert "next:" not in result.stdout


def test_absent_runtime_and_missing_mise_fail(tmp_path: Path) -> None:
    scaffold(tmp_path)
    manifest(tmp_path, "web/package.json")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert "missing on PATH: bun" in result.stderr
    (tmp_path / ".mise.toml").write_text("[tools]\n")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert "mise is required" in result.stderr


def test_credentials_explicit_stable_private_and_preserve_process_values(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "LOCAL_ACCESS_TOKEN=\nPROVIDER_API_KEY=\nPROVIDER_SECRET=\nJWT_SIGNING_KEY=\nENCRYPTION_KEY_RUST=\nPOSTGRES_PASSWORD=supplied-fixture\n")
    declarations = tmp_path / "scripts/config/generated-credentials.conf"
    with declarations.open("a") as handle:
        handle.write("LOCAL_ACCESS_TOKEN hex32\n")
    result = run_setup(tmp_path, JWT_SIGNING_KEY="injected-fixture", ENCRYPTION_KEY_RUST="injected-encryption")
    assert result.returncode == 0, result.stdout + result.stderr
    original = (tmp_path / ".env").read_text()
    values = dict(line.split("=", 1) for line in original.splitlines())
    assert len(values["LOCAL_ACCESS_TOKEN"]) == 64
    assert values["PROVIDER_API_KEY"] == values["PROVIDER_SECRET"] == ""
    assert values["JWT_SIGNING_KEY"] == values["ENCRYPTION_KEY_RUST"] == ""
    assert values["POSTGRES_PASSWORD"] == "supplied-fixture"
    assert "REDIS_PASSWORD" not in values
    assert (tmp_path / ".env").stat().st_mode & 0o777 == 0o600
    assert values["LOCAL_ACCESS_TOKEN"] not in result.stdout + result.stderr
    assert "fixture" not in result.stdout + result.stderr
    with (tmp_path / ".env.template").open("a") as handle:
        handle.write("NEW_FLAG=0\n")
    result = run_setup(tmp_path, JWT_SIGNING_KEY="injected-fixture", ENCRYPTION_KEY_RUST="injected-encryption")
    assert result.returncode == 0, result.stderr
    assert (tmp_path / ".env").read_text() == original + "NEW_FLAG=0\n"


def test_activation_preserves_winning_environment_and_targeted_require_does_not_install(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "APP_SETTING=file-value\n")
    fake_mise(tmp_path, activation='printf \'export PATH="%s/tools:$PATH"\\nexport APP_SETTING=wrong\\nexport INJECTED=wrong\\nexport DATA_DIR=wrong\\n\' "$CTL_ROOT"')
    executable(tmp_path / "tools/bun", '[[ "$APP_SETTING" == file-value && "$INJECTED" == injected-value ]]\n')
    manifest(tmp_path, "web/package.json")
    result = run_setup(tmp_path, INJECTED="injected-value", DATA_DIR="./custom data")
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "custom data/postgres").is_dir()
    (tmp_path / "mise.calls").unlink()
    script = 'source "$CTL_ROOT/scripts/common/_lib.sh"; cd "$CTL_ROOT"; require_env; require_tools bun'
    result = subprocess.run(["/bin/bash", "-euc", script], env={
        "CTL_ROOT": str(tmp_path), "PATH": str(tmp_path / "bin"), "APP_SETTING": "file-value",
        "INJECTED": "injected-value", "HOME": str(tmp_path),
    }, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "mise.calls").read_text().splitlines() == ["env -s bash"]


def test_real_cargo_workspace_dedup_preserves_excluded_nested_crate(tmp_path: Path) -> None:
    cargo = shutil.which("cargo")
    if cargo is None:
        pytest.skip("cargo is required to prove real workspace membership")
    scaffold(tmp_path)
    manifest(tmp_path, "engine/Cargo.toml", '[workspace]\nmembers = ["crates/member"]\nexclude = ["independent"]\nresolver = "2"\n')
    for directory, name in (("engine/crates/member", "member"), ("engine/independent", "independent")):
        manifest(tmp_path, f"{directory}/Cargo.toml", f'[package]\nname = "{name}"\nversion = "0.1.0"\nedition = "2021"\n')
        manifest(tmp_path, f"{directory}/src/lib.rs")
    manifest(tmp_path, "engine/target/decoy/Cargo.toml", "<version>")
    executable(tmp_path / "bin/cargo", 'printf "%s|%s\\n" "$PWD" "$*" >> "$CTL_ROOT/cargo.calls"\n'
               + f'exec {shlex.quote(cargo)} "$@"\n')
    result = run_setup(tmp_path, HOME=os.environ["HOME"], CARGO_NET_OFFLINE="true")
    assert result.returncode == 0, result.stdout + result.stderr
    fetches = [line for line in (tmp_path / "cargo.calls").read_text().splitlines() if line.endswith("|fetch")]
    assert sorted(fetches) == sorted([f"{tmp_path}/apps/engine|fetch", f"{tmp_path}/apps/engine/independent|fetch"])


@pytest.mark.parametrize("operation", ["locate-project", "fetch"])
def test_cargo_discovery_and_fetch_failure(tmp_path: Path, operation: str) -> None:
    scaffold(tmp_path)
    manifest(tmp_path, "engine/Cargo.toml")
    executable(tmp_path / "bin/cargo", f'[[ "$1" != {operation} ]] || exit 7\n'
               'if [[ "$1" == locate-project ]]; then printf "%s/apps/engine/Cargo.toml\\n" "$CTL_ROOT"; fi\n')
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert "cargo" in result.stderr
    assert "next:" not in result.stdout


def test_generation_failure_stops_without_writing_secret(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "JWT_SIGNING_KEY=\n")
    (tmp_path / "bin/openssl").unlink()
    executable(tmp_path / "bin/openssl", "exit 8\n")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert "generation failed for JWT_SIGNING_KEY" in result.stderr
    assert (tmp_path / ".env").read_text() == ENV + "JWT_SIGNING_KEY=\n"


def test_require_openssl_uses_its_version_command(tmp_path: Path) -> None:
    scaffold(tmp_path)
    (tmp_path / "bin/openssl").unlink()
    executable(tmp_path / "bin/openssl", '[[ "$*" == version ]]\n')
    result = subprocess.run(["/bin/bash", "-euc", 'source "$CTL_ROOT/scripts/common/_lib.sh"; require_tools openssl'],
                            env={"CTL_ROOT": str(tmp_path), "PATH": str(tmp_path / "bin")},
                            capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr


def test_explicit_empty_process_credential_is_preserved_but_fails(tmp_path: Path) -> None:
    scaffold(tmp_path, ENV + "JWT_SIGNING_KEY=\n")
    result = run_setup(tmp_path, JWT_SIGNING_KEY="")
    assert result.returncode != 0
    assert "required local credential is blank: JWT_SIGNING_KEY" in result.stderr
    assert (tmp_path / ".env").read_text() == ENV + "JWT_SIGNING_KEY=\n"
    assert "next:" not in result.stdout


@pytest.mark.parametrize("present", [True, False])
def test_required_provider_credential_is_never_generated(tmp_path: Path, present: bool) -> None:
    scaffold(tmp_path, ENV + ("PROVIDER_API_KEY=\n" if present else ""))
    (tmp_path / "scripts/config/required-credentials.conf").write_text("PROVIDER_API_KEY\n")
    result = run_setup(tmp_path)
    assert result.returncode != 0
    assert "PROVIDER_API_KEY" in result.stderr
    assert "next:" not in result.stdout
    if present:
        result = run_setup(tmp_path, PROVIDER_API_KEY="provided-fixture")
        assert result.returncode == 0, result.stderr
        assert "provided-fixture" not in result.stdout + result.stderr
        assert (tmp_path / ".env").read_text().endswith("PROVIDER_API_KEY=\n")
