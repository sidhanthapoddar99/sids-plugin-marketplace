"""Render the shipped Compose models without starting containers."""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

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


@pytest.mark.parametrize("config", ["base"])
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


@pytest.mark.parametrize("value", ["state", "state with spaces"])
@pytest.mark.parametrize("config", ["base"])
def test_compose_normalizes_bare_relative_storage(compose_root: Path, value: str, config: str) -> None:
    env_file = compose_root / ".env"
    env_file.write_text(env_file.read_text().replace("DATA_DIR=./data", f"DATA_DIR={value}"))
    model = render(compose_root, config)
    mount = model["services"]["postgres"]["volumes"][0]
    assert mount["type"] == "bind"
    assert mount["source"] == str(compose_root / value / "postgres/pgdata")


def test_compose_rejects_blank_storage_before_invoking_docker(tmp_path: Path) -> None:
    marker = tmp_path / "docker-invoked"
    script = 'source "$1"; marker=$2; docker() { : > "$marker"; }; export DATA_DIR=""; compose_cmd config'
    result = subprocess.run(
        ["bash", "-c", script, "bash", str(TEMPLATE / "scripts/common/_lib.sh"), str(marker)],
        env={"PATH": os.environ["PATH"], "CTL_ROOT": str(tmp_path)},
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
    assert "DATA_DIR is blank" in result.stderr
    assert not marker.exists()


def test_dev_preset_selects_only_data_core_with_loopback_ports(compose_root: Path) -> None:
    presets = yaml.safe_load((compose_root / "docker/presets.yaml").read_text())
    arguments = shlex.split(presets["dev"])
    assert arguments[arguments.index("--config") + 1] == "base"
    assert "+expose_db" in arguments
    selected = set(arguments[arguments.index("--services") + 1].split(","))
    assert selected == {"postgres", "redis", "neo4j", "migrate", "neo4j-init"}
    model = render(compose_root, "base", "m.expose_db")
    dependencies = set(selected)
    for service in selected:
        dependencies.update(model["services"][service].get("depends_on", {}))
    assert dependencies == selected
    assert not selected.intersection({"api", "engine", "web", "dashboard"})
    for service in ("postgres", "redis", "neo4j"):
        assert all(port["host_ip"] == "127.0.0.1" for port in model["services"][service]["ports"])


def test_base_is_self_contained_without_development_proxy(compose_root: Path) -> None:
    model = render(compose_root, "base")
    assert set(model["services"]) == {"api", "engine", "web", "dashboard", "postgres", "redis", "neo4j", "migrate", "neo4j-init"}
    assert all(not service.get("ports") and service.get("network_mode") != "host" for service in model["services"].values())
    assert not (compose_root / "docker/compose.db.yaml").exists()
    assert not (compose_root / "docker/compose.dev.yaml").exists()
