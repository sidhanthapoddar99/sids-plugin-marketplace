"""Render the shipped Compose models without starting containers."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"


@pytest.fixture
def compose_root(tmp_path: Path) -> Path:
    if not shutil.which("docker"):
        pytest.skip("Docker CLI unavailable")
    version = subprocess.run(["docker", "compose", "version"], capture_output=True, check=False)
    if version.returncode:
        pytest.skip("Docker Compose unavailable")
    shutil.copytree(TEMPLATE / "docker", tmp_path / "docker")
    shutil.copy(TEMPLATE / ".env.template", tmp_path / ".env")
    with (tmp_path / ".env").open("a") as handle:
        handle.write("UNDECLARED_SECRET=synthetic-private-sentinel\n")
    return tmp_path


def render(root: Path, *files: str) -> dict:
    env = {
        "PATH": os.environ["PATH"], "HOME": str(root), "CTL_ROOT": str(root), "NO_COLOR": "1",
        "COMPOSE_PROJECT_NAME": "env-contract-test", "REGISTRY": "ghcr.io/example", "TAG": "test",
        "POSTGRES_PASSWORD": "synthetic-password", "WEB_LANDING_PORT": "4301",
        "PUBLIC_URL": "https://example.test", "HTTP_PORT": "8085", "HTTPS_PORT": "8445",
    }
    command = 'source "$1"; shift; cd "$CTL_ROOT"; require_env; compose_cmd "$@" config --format json'
    args = ["bash", "-c", command, "bash", str(TEMPLATE / "scripts/common/_lib.sh")]
    for name in files:
        args.extend(["-f", f"docker/compose.{name}.yaml"])
    result = subprocess.run(args, env=env, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


@pytest.mark.parametrize("config", ["base", "db", "dev"])
def test_configs_render_without_undeclared_secrets(compose_root: Path, config: str) -> None:
    model = render(compose_root, config)
    assert model["services"]
    assert "synthetic-private-sentinel" not in json.dumps(model)
    for service in model["services"].values():
        assert "env_file" not in service
        assert "synthetic-password" not in json.dumps(service.get("build", {}).get("args", {}))


@pytest.mark.parametrize("modifier", ["expose_web", "expose", "expose_db", "env_override", "public"])
def test_modifiers_render_and_use_process_overrides(compose_root: Path, modifier: str) -> None:
    model = render(compose_root, "base", f"m.{modifier}")
    assert "synthetic-private-sentinel" not in json.dumps(model)
    assert model["services"]["postgres"]["environment"]["POSTGRES_PASSWORD"] == "synthetic-password"
    if modifier == "expose_web":
        assert model["services"]["web"]["ports"][0]["published"] == "4301"
    if modifier == "env_override":
        assert model["services"]["api"]["environment"]["DATABASE_URL"] == (
            "postgresql://app:synthetic-password@localhost:5432/app"
        )
