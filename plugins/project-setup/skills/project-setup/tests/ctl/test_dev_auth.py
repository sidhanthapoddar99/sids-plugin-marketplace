"""Development sign-in: the env key, compose, the migration and both example backends agree.

The example backends cannot run their own suites in place, because their manifests hold
`<version>` placeholders until a project resolves them. So this suite copies each example's
auth rules into a scratch folder and runs its tests there, with no application dependency.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from test_compose import compose_root, render  # noqa: F401  (compose_root is a fixture)

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
MIGRATIONS = TEMPLATE / "apps/database/postgres/migrations"
API = TEMPLATE / "apps/example-api-python"
ENGINE = TEMPLATE / "apps/example-engine-rust"
RESERVED = "00000000-0000-4000-8000-000000000001"
UUID_TEXT = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
MODIFIERS = sorted(p.name[len("compose.m.") : -len(".yaml")] for p in (TEMPLATE / "docker").glob("compose.m.*.yaml"))


def sql(name: str) -> str:
    """The migration's statements, with comments removed and whitespace collapsed."""
    text = re.sub(r"--[^\n]*", "", (MIGRATIONS / name).read_text())
    return " ".join(text.split())


def test_the_switch_sits_between_debugging_and_service_addresses() -> None:
    text = (TEMPLATE / ".env.template").read_text()
    headers = [text.index(f"# {name} #") for name in ("DEBUGGING", "AUTHENTICATION", "SERVICE ADDRESSES")]
    assert headers == sorted(headers)
    section = text[headers[1] : headers[2]]
    assert re.findall(r"^AUTH_ENABLED=.*$", text, re.M) == ["AUTH_ENABLED=FALSE"]
    assert "AUTH_ENABLED=FALSE" in section


def test_the_reference_page_shows_the_template_section_as_it_is() -> None:
    page = (TEMPLATE.parent / "references/14_development-sign-in.md").read_text()
    blocks = re.findall(r"```dotenv\n(.*?)```", page, re.S)
    assert len(blocks) == 1
    assert blocks[0] in (TEMPLATE / ".env.template").read_text()


@pytest.mark.parametrize("app", [API, ENGINE], ids=["api", "engine"])
def test_each_backend_reads_the_switch_through_its_config(app: Path) -> None:
    config = yaml.safe_load((app / "config.yaml").read_text())
    assert config["auth"]["enabled"] == "${AUTH_ENABLED}"


@pytest.mark.parametrize("modifier", [None, *MODIFIERS])
def test_containers_always_require_sign_in(compose_root: Path, modifier: str | None) -> None:  # noqa: F811
    assert "AUTH_ENABLED=FALSE" in (compose_root / ".env").read_text()
    files = ["base"] if modifier is None else ["base", f"m.{modifier}"]
    services = render(compose_root, *files)["services"]
    assert {name: services[name]["environment"]["AUTH_ENABLED"] for name in ("api", "engine")} == {
        "api": "TRUE",
        "engine": "TRUE",
    }


def test_compose_states_the_switch_as_a_literal() -> None:
    base = (TEMPLATE / "docker/compose.base.yaml").read_text().splitlines()
    lines = [line.split("#")[0].strip() for line in base]
    assert [line for line in lines if line.startswith("AUTH_ENABLED")] == ['AUTH_ENABLED: "TRUE"'] * 2
    for modifier in (TEMPLATE / "docker").glob("compose.m.*.yaml"):
        assert "AUTH_ENABLED" not in modifier.read_text(), modifier.name


def test_every_frontend_dev_server_binds_loopback() -> None:
    # A dev server's proxy turns a request from any address it listens on into a loopback request,
    # which a backend under FALSE would give the reserved user.
    vite = sorted(TEMPLATE.glob("apps/**/vite.config.ts"))
    for config in vite:
        assert re.search(r'host:\s*"127\.0\.0\.1"', config.read_text()), config
    scripts = [(path, json.loads(path.read_text()).get("scripts", {}).get("dev", ""))
               for path in sorted(TEMPLATE.glob("apps/**/package.json"))]
    nextjs = [(path, dev) for path, dev in scripts if dev.startswith("next dev")]
    for path, dev in nextjs:
        assert "--hostname 127.0.0.1" in dev, path
    assert vite and nextjs


def test_migrations_are_flyway_versions_in_order() -> None:
    names = sorted(p.name for p in MIGRATIONS.glob("*.sql"))
    assert all(re.fullmatch(r"V\d+__[a-z0-9_]+\.sql", name) for name in names), names
    versions = [int(name[1:].split("__")[0]) for name in names]
    assert sorted(versions)[:3] == [1, 2, 3]
    assert "V2__users.sql" in names and "V3__development_identity.sql" in names


def test_the_users_table_has_room_for_an_account_with_no_password() -> None:
    statement = sql("V2__users.sql")
    assert "CREATE TABLE users (" in statement
    assert "username text NOT NULL UNIQUE" in statement
    assert re.search(r"password_hash text(,| \))", statement), statement


def test_the_migration_reserves_one_identity_and_never_adopts_an_account() -> None:
    statement = sql("V3__development_identity.sql")
    assert "ADD COLUMN development_identity boolean NOT NULL DEFAULT false" in statement
    assert f"CHECK (development_identity = (id = '{RESERVED}'))" in statement
    assert "CHECK (NOT development_identity OR password_hash IS NULL)" in statement
    assert (
        "INSERT INTO users (id, username, password_hash, development_identity) "
        f"VALUES ('{RESERVED}', 'default', NULL, true);"
    ) in statement
    # A plain INSERT: a collision fails the migration instead of adopting or resetting a row.
    assert not re.search(r"\b(ON CONFLICT|UPDATE|DELETE|MERGE|IF NOT EXISTS)\b", statement, re.I)
    assert set(UUID_TEXT.findall(statement)) == {RESERVED}


def test_backends_name_the_id_the_migration_reserves() -> None:
    python = (API / "app/core/auth.py").read_text()
    rust = (ENGINE / "crates/auth/src/identity.rs").read_text()
    assert re.findall(r'^RESERVED_USER_ID = UUID\("([^"]+)"\)$', python, re.M) == [RESERVED]
    assert re.findall(r'^pub const RESERVED_USER_ID: &str = "([^"]+)";$', rust, re.M) == [RESERVED]


def test_python_example_rules_pass(tmp_path: Path) -> None:
    shutil.copytree(API / "app", tmp_path / "app")
    env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "app/core/test_auth.py"],
        cwd=tmp_path, env=env, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert re.search(r"\d+ passed", result.stdout), result.stdout


def test_rust_example_rules_pass(tmp_path: Path) -> None:
    cargo = shutil.which("cargo")
    if cargo is None:
        pytest.skip("cargo is required to run the engine's auth rules")
    for crate in ("common", "auth"):
        shutil.copytree(ENGINE / "crates" / crate, tmp_path / "crates" / crate)
    # A resolved stand-in for the root manifest, whose edition is a `<version>` placeholder.
    (tmp_path / "Cargo.toml").write_text(
        '[workspace]\nresolver = "2"\nmembers = ["crates/common", "crates/auth"]\n\n'
        '[workspace.package]\nversion = "0.1.0"\nedition = "2021"\n'
    )
    env = {**os.environ, "CARGO_TARGET_DIR": str(tmp_path / "target")}
    result = subprocess.run(
        [cargo, "test", "--offline", "--quiet"], cwd=tmp_path, env=env, capture_output=True, text=True, check=False
    )
    assert result.returncode == 0, result.stdout + result.stderr
    # Both crates ran tests: an empty crate also prints "test result: ok. 0 passed".
    passed = [int(n) for n in re.findall(r"test result: ok\. (\d+) passed", result.stdout)]
    assert len([n for n in passed if n > 0]) == 2, result.stdout
