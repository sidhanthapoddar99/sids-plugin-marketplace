"""ctl deploys: the rollback guard, the deploy record, image retention and pull_policy: never.

A deploy is a ctl up with TAG=auto or a pinned tag. The suite runs the real up.sh, migrate.sh and
check.sh in a scratch git repository, against the recording docker shim of test_up_lifecycle.py, so a
refused rollback is proven to reach no activation, and a retention run is proven to touch only the
repositories ctl builds.
"""

import subprocess
from pathlib import Path

import pytest
import yaml

from test_image_tag import GIT_ENV, git
from test_up_lifecycle import calls, fixture_env

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
UP = TEMPLATE / "scripts/container/up.sh"
MIGRATE = TEMPLATE / "scripts/db/migrate.sh"
CHECK = TEMPLATE / "scripts/config/check.sh"
MIGRATIONS = "apps/database/postgres/migrations"


def deploy_repo(root: Path, services: dict | None = None, **options: object) -> dict[str, str]:
    """A committed checkout whose one built service is api; the fixture files stay ignored."""
    env = {**fixture_env(root, services or {"api": {"build": ".", "image": "example/api:current"}}, **options), **GIT_ENV}
    (root / ".gitignore").write_text(".env\ncalls.jsonl\n*.count\nbin/\nfixture.json\ndata/\n")
    (root / MIGRATIONS).mkdir(parents=True)
    (root / MIGRATIONS / "V1__start.sql").write_text("CREATE TABLE a (id int);\n")
    git(root, "init", "-q", "-b", "main")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "TEST FIXTURE start")
    return env


def commit(root: Path, name: str, *, migration: bool = False) -> str:
    """A new commit that changes app code, or adds a migration; returns its full hash."""
    path = root / MIGRATIONS / f"V2__{name}.sql" if migration else root / "apps/api.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{name}\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", f"TEST FIXTURE {name}")
    return git(root, "rev-parse", "HEAD")


def up(env: dict[str, str], *flags: str, **shell: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(UP), "--config", "fixture", "--nqa", "-y", *flags],
                          env={**env, **shell}, text=True, capture_output=True, timeout=20)


def record(root: Path) -> Path:
    return root / "data/deployed-commit"


def write_record(root: Path, commit_hash: str) -> None:
    record(root).parent.mkdir(exist_ok=True)
    record(root).write_text(commit_hash + "\n")


def activated(root: Path) -> bool:
    return (root / "calls.jsonl").exists() and bool(calls(root, "up"))


def test_first_deploy_is_allowed_and_records_the_commit(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert record(tmp_path).read_text() == git(tmp_path, "rev-parse", "HEAD") + "\n"


def test_forward_and_same_commit_deploys_are_allowed(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    assert up(env, TAG="auto").returncode == 0
    ahead = commit(tmp_path, "ahead", migration=True)
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert record(tmp_path).read_text() == ahead + "\n"
    result = up(env, "--no-build", TAG=ahead[:8])
    assert result.returncode == 0, result.stderr
    assert "rolls back" not in result.stderr


@pytest.mark.parametrize("build", [True, False])
@pytest.mark.parametrize("target", ["pinned", "auto"])
def test_a_rollback_is_refused_by_default(tmp_path: Path, target: str, build: bool) -> None:
    env = deploy_repo(tmp_path)
    older = git(tmp_path, "rev-parse", "HEAD")
    newer = commit(tmp_path, "newer")
    write_record(tmp_path, newer)
    if target == "auto":
        git(tmp_path, "checkout", "-q", older)
    result = up(env, *([] if build else ["--no-build"]), TAG=older[:8] if target == "pinned" else "auto")
    assert result.returncode != 0
    assert f"is a rollback: {older[:8]} is not ahead of the last deploy {newer[:8]}" in result.stderr
    assert "ROLLBACK=off refuses every rollback" in result.stderr
    assert not activated(tmp_path)
    assert record(tmp_path).read_text() == newer + "\n"


@pytest.mark.parametrize("setting", ["", "off"])
def test_off_and_empty_refuse_a_rollback(tmp_path: Path, setting: str) -> None:
    env = deploy_repo(tmp_path)
    older = git(tmp_path, "rev-parse", "HEAD")
    write_record(tmp_path, commit(tmp_path, "newer"))
    result = up(env, TAG=older[:8], ROLLBACK=setting)
    assert result.returncode != 0
    assert "ROLLBACK=off refuses every rollback" in result.stderr
    assert not activated(tmp_path)


def test_another_line_of_history_is_a_rollback(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    git(tmp_path, "checkout", "-q", "-b", "side")
    write_record(tmp_path, commit(tmp_path, "side"))
    git(tmp_path, "checkout", "-q", "main")
    commit(tmp_path, "main")
    result = up(env, TAG="auto")
    assert result.returncode != 0
    assert "ROLLBACK=off refuses every rollback" in result.stderr
    assert not activated(tmp_path)


def test_on_allows_a_rollback_that_crosses_no_migration(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    older = git(tmp_path, "rev-parse", "HEAD")
    write_record(tmp_path, commit(tmp_path, "newer"))
    result = up(env, "--no-build", TAG=older[:8], ROLLBACK="on")
    assert result.returncode == 0, result.stderr
    assert "ROLLBACK=on, and no file under apps/database differs" in result.stderr
    assert activated(tmp_path)
    assert record(tmp_path).read_text() == older + "\n"


def test_on_refuses_a_rollback_across_a_migration(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    older = git(tmp_path, "rev-parse", "HEAD")
    newer = commit(tmp_path, "next", migration=True)
    write_record(tmp_path, newer)
    result = up(env, "--no-build", TAG=older[:8], ROLLBACK="on")
    assert result.returncode != 0
    assert "across a migration, which ROLLBACK=on refuses too" in result.stderr
    assert f"{MIGRATIONS}/V2__next.sql" in result.stderr
    assert not activated(tmp_path)
    assert record(tmp_path).read_text() == newer + "\n"


def test_a_pinned_tag_must_name_a_commit(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    result = up(env, TAG="1.4.2")
    assert result.returncode != 0
    assert "TAG=1.4.2 names no commit" in result.stderr
    assert not activated(tmp_path)
    git(tmp_path, "tag", "1.4.2")
    result = up(env, TAG="1.4.2")
    assert result.returncode == 0, result.stderr
    assert record(tmp_path).read_text() == git(tmp_path, "rev-parse", "HEAD") + "\n"


@pytest.mark.parametrize(("content", "failure"), [
    ("f" * 40, "which this checkout does not have"),
    ("not a commit", "holds no commit"),
])
def test_a_record_ctl_cannot_compare_is_refused(tmp_path: Path, content: str, failure: str) -> None:
    env = deploy_repo(tmp_path)
    write_record(tmp_path, content)
    result = up(env, TAG="auto")
    assert result.returncode != 0
    assert failure in result.stderr
    assert str(record(tmp_path)) in result.stderr
    assert not activated(tmp_path)


@pytest.mark.parametrize(("options", "written"), [
    ({"build_exit": 17}, False),   # the build failed: nothing started
    ({"up_exit": 5}, True),         # activation began, so a migration may have run
    ({"states": {"api": [{"Status": "exited", "ExitCode": 3}]}}, True),   # readiness failed after activation
])
def test_the_record_is_written_once_activation_begins(tmp_path: Path, options: dict, written: bool) -> None:
    env = deploy_repo(tmp_path, **options)
    result = up(env, TAG="auto")
    assert result.returncode != 0
    assert record(tmp_path).exists() == written


def test_an_unknown_rollback_setting_is_an_error(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path)
    for tag in ("auto", "dev"):
        result = up(env, TAG=tag, ROLLBACK="maybe")
        assert result.returncode != 0
        assert "ROLLBACK=maybe — use off" in result.stderr
    assert not activated(tmp_path)


def retention_repo(root: Path, **options: object) -> dict[str, str]:
    images = {
        "example/api": [
            {"tag": "current", "created": "2026-10-29T10:00:00.12Z"},
            {"tag": "t4", "created": "2026-10-29T10:00:00.1Z"},    # newer than t3 by its fraction
            {"tag": "t3", "created": "2026-10-28T10:00:00Z"},
            {"tag": "t2", "created": "2026-10-27T10:00:00.5Z"},
            {"tag": "t1", "created": "2026-10-26T10:00:00Z"},
        ],
        "example/web": [
            {"tag": "current", "created": "2026-10-29T10:00:00Z"},
            {"tag": "t1", "created": "2026-10-26T10:00:00Z"},
        ],
        "postgres": [{"tag": f"1{n}", "created": f"2026-01-0{n}T00:00:00Z"} for n in range(1, 6)],
    }
    services = {
        "api": {"build": ".", "image": "example/api:current"},
        "web": {"build": ".", "image": "example/web:current"},
        "postgres": {"image": "postgres:15"},
    }
    return deploy_repo(root, services, images=images, **options)


def removed(root: Path) -> list[str]:
    return [args[-1] for args in calls(root, "rm")]


def test_retention_keeps_the_newest_tags_and_spares_used_images_and_other_repositories(tmp_path: Path) -> None:
    env = retention_repo(tmp_path, in_use=["example/api:t2"])
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert sorted(removed(tmp_path)) == ["example/api:t1", "example/api:t3"]
    assert "kept example/api:t2: a container uses it" in result.stdout
    assert "image retention: removed example/api:t3 example/api:t1" in result.stdout
    listed = {args[-1] for args in calls(tmp_path, "ls")}
    assert listed == {"example/api", "example/web"}


def test_retention_never_fails_the_deploy(tmp_path: Path) -> None:
    env = retention_repo(tmp_path, rm_exit=1)
    result = up(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert "docker could not remove example/api:t3; kept" in result.stderr


def test_retention_runs_in_the_foreground_too(tmp_path: Path) -> None:
    env = retention_repo(tmp_path, logs_exit=0)
    result = up(env, "-a", TAG="auto")
    assert "image retention: removed" in result.stdout, result.stdout + result.stderr
    assert record(tmp_path).exists()


@pytest.mark.parametrize("tag", ["dev", "dev-slot-2", "none", None])
def test_local_builds_make_no_record_and_remove_nothing(tmp_path: Path, tag: str | None) -> None:
    env = retention_repo(tmp_path)
    write_record(tmp_path, "f" * 40)
    assert up(env, TAG="auto").returncode != 0   # a deploy refuses this record; a local build never reads it
    result = up(env, **({} if tag is None else {"TAG": tag}))
    assert result.returncode == 0, result.stderr
    assert record(tmp_path).read_text() == "f" * 40 + "\n"
    assert not calls(tmp_path, "image")


def migrate(env: dict[str, str], **shell: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(MIGRATE), "up"], env={**env, **shell}, text=True, capture_output=True, timeout=20)


def test_db_migrate_up_passes_the_guard_and_moves_the_record(tmp_path: Path) -> None:
    env = deploy_repo(tmp_path, running=["postgres"])
    older = git(tmp_path, "rev-parse", "HEAD")
    newer = commit(tmp_path, "next", migration=True)
    result = migrate(env, TAG="auto")
    assert result.returncode == 0, result.stderr
    assert record(tmp_path).read_text() == newer + "\n"
    git(tmp_path, "checkout", "-q", older)
    for result in (migrate(env, TAG="auto"), up(env, TAG="auto")):
        assert result.returncode != 0
        assert "ROLLBACK=off refuses every rollback" in result.stderr
    assert len(calls(tmp_path, "run")) == 1
    assert not activated(tmp_path)


def compose_services() -> list[tuple[str, str, dict]]:
    return [
        (path.name, name, service)
        for path in sorted((TEMPLATE / "docker").glob("compose*.yaml"))
        for name, service in (yaml.safe_load(path.read_text()).get("services") or {}).items()
    ]


def test_every_built_service_never_pulls_and_third_party_images_are_untouched() -> None:
    built = [(file, name) for file, name, service in compose_services() if "build" in service]
    assert built, "the template builds no service"
    for file, name, service in compose_services():
        if "build" in service:
            assert service.get("pull_policy") == "never", f"{file}: {name} builds from source without pull_policy: never"
        else:
            assert "pull_policy" not in service, f"{file}: {name} is a third-party image; leave its pull policy alone"


@pytest.mark.parametrize("policy", [None, "never"])
def test_check_names_a_built_service_without_pull_policy_never(tmp_path: Path, policy: str | None) -> None:
    api = {"build": ".", "image": "example/api:dev", **({"pull_policy": policy} if policy else {})}
    env = fixture_env(tmp_path, {"api": api, "postgres": {"image": "postgres:15"}})
    result = subprocess.run(["bash", str(CHECK)], env=env, text=True, capture_output=True, timeout=60)
    if policy:
        assert "config fixture: every built service has pull_policy: never" in result.stdout, result.stdout + result.stderr
    else:
        assert "config fixture: api built from source without pull_policy: never" in result.stderr, result.stderr


@pytest.mark.parametrize(("setting", "passes"), [("off", True), ("on", True), ("", True), ("maybe", False)])
def test_check_names_an_unknown_rollback_setting(tmp_path: Path, setting: str, passes: bool) -> None:
    env = fixture_env(tmp_path, {"api": {"build": ".", "image": "example/api:dev", "pull_policy": "never"}})
    (tmp_path / ".env").write_text(f"FIXTURE_ONLY=1\nROLLBACK={setting}\n")
    result = subprocess.run(["bash", str(CHECK)], env=env, text=True, capture_output=True, timeout=60)
    if passes:
        assert f"ROLLBACK is {setting or 'off'}" in result.stdout, result.stdout + result.stderr
    else:
        assert "ROLLBACK=maybe — use off" in result.stderr
        assert "ctl up and ctl db migrate up would stop on ROLLBACK" in result.stderr
