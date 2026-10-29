"""ctl image tags: TAG is dev, auto, none or a tag used as written, resolved once for every compose call.

The suite runs the real shell library (scripts/common/_lib.sh and _compose_start.sh) in a scratch git
repository with an isolated git configuration. A recording docker shim stores each call with the TAG
compose would read from the shell, so a refused build is proven to reach no docker command at all.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from test_up_lifecycle import calls, fixture_env

COMMON = Path(__file__).resolve().parents[2] / "template/scripts/common"
GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "TEST FIXTURE", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
    "GIT_COMMITTER_NAME": "TEST FIXTURE", "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
}
SHIM = r'''
import json, os, sys
from pathlib import Path
with (Path(os.environ["CTL_ROOT"]) / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps({"tag": os.environ.get("TAG"), "args": sys.argv[1:]}) + "\n")
'''


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], env={**os.environ, **GIT_ENV},
                          check=True, capture_output=True, text=True).stdout.strip()


def repo(root: Path, env_text: str = "REGISTRY=example\nTAG=dev\n", *, commit: bool = True) -> Path:
    (root / "bin").mkdir(parents=True)
    (root / "bin/docker").write_text(f"#!{sys.executable}\n" + SHIM)
    (root / "bin/docker").chmod(0o755)
    (root / "docker").mkdir()
    (root / "docker/compose.base.yaml").write_text("services:\n  api:\n    image: ${REGISTRY}/api:${TAG}\n    build: .\n")
    (root / ".env").write_text(env_text)
    (root / ".gitignore").write_text(".env\ncalls.jsonl\nbin/\n")
    if commit:
        git(root, "init", "-q", "-b", "main")
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "TEST FIXTURE")
    return root


def run(root: Path, body: str, **shell: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": f"{root / 'bin'}{os.pathsep}{os.environ['PATH']}", "HOME": str(root), "NO_COLOR": "1",
           "CTL_ROOT": str(root), "COMMON": str(COMMON), **GIT_ENV, **shell}
    script = f'set -euo pipefail; source "$COMMON/_lib.sh"; cd "$CTL_ROOT"; {body}'
    return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, timeout=30)


def resolved(root: Path, **shell: str) -> str:
    result = run(root, 'require_env; printf "%s|%s\\n" "${TAG-}" "$(image_tag_label)"', **shell)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def builds(root: Path) -> list[dict]:
    path = root / "calls.jsonl"
    entries = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    return [entry for entry in entries if "build" in entry["args"]]


def head(root: Path) -> str:
    return git(root, "rev-parse", "--short=8", "HEAD")


def test_dev_is_used_as_written(tmp_path: Path) -> None:
    assert resolved(repo(tmp_path)) == "dev|dev"


def test_auto_is_the_checkouts_commit(tmp_path: Path) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n")
    commit = head(root)
    assert len(commit) >= 8
    assert resolved(root) == f"{commit}|auto → {commit}"


def test_auto_builds_from_a_clean_checkout_and_compose_reads_the_commit(tmp_path: Path) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n")
    result = run(root, "require_env; dc_build api")
    assert result.returncode == 0, result.stderr
    assert [entry["tag"] for entry in builds(root)] == [head(root)]


@pytest.mark.parametrize("change", ["untracked", "tracked"])
def test_auto_refuses_a_build_from_a_checkout_with_uncommitted_changes(tmp_path: Path, change: str) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n")
    if change == "untracked":
        (root / "notes.txt").write_text("not committed\n")
    else:
        (root / "docker/compose.base.yaml").write_text("services: {}\n")
    result = run(root, "require_env; dc_build api")
    assert result.returncode != 0
    assert f"after commit {head(root)}" in result.stderr
    assert "commit them, or set TAG=dev" in result.stderr
    assert builds(root) == []


def test_an_ignored_file_leaves_the_checkout_clean(tmp_path: Path) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n")
    (root / ".env").write_text("REGISTRY=example\nTAG=auto\nLOCAL=1\n")   # .env is ignored, as in the template
    assert run(root, "require_env; dc_build api").returncode == 0


@pytest.mark.parametrize("build", [True, False])
def test_compose_start_refuses_only_the_build_on_a_dirty_auto_checkout(tmp_path: Path, build: bool) -> None:
    env = {**fixture_env(tmp_path, {"api": {"build": "."}}), **GIT_ENV, "TAG": "auto"}
    git(tmp_path, "init", "-q", "-b", "main")
    git(tmp_path, "commit", "-q", "--allow-empty", "-m", "TEST FIXTURE")   # the fixture files stay untracked
    script = (
        'set -euo pipefail; source "$1/_lib.sh"; source "$1/_compose_start.sh"; image_tag_resolve; '
        'mapfile -t compose_base < <(compose_argv -f docker/compose.fixture.yaml); shift; compose_start "$@"'
    )
    argv = ["bash", "-c", script, "bash", str(COMMON), *([] if build else ["--no-build"]), "0", "3", "api"]
    result = subprocess.run(argv, env=env, text=True, capture_output=True, timeout=12)
    if build:
        assert result.returncode != 0
        assert "uncommitted changes" in result.stderr
        assert not (tmp_path / "calls.jsonl").exists() or calls(tmp_path, "build") == calls(tmp_path, "up") == []
    else:
        assert result.returncode == 0, result.stderr
        assert calls(tmp_path, "build") == []
        assert len(calls(tmp_path, "up")) == 1


@pytest.mark.parametrize("tag", ["1.4.2", "v2.0.0-rc.1", "f5744bff", "a" * 40])
def test_a_pinned_tag_is_used_as_written(tmp_path: Path, tag: str) -> None:
    assert resolved(repo(tmp_path, f"REGISTRY=example\nTAG={tag}\n")) == f"{tag}|{tag}"


def test_a_tag_set_in_the_shell_beats_the_env_file(tmp_path: Path) -> None:
    root = repo(tmp_path)
    assert resolved(root, TAG="f00dcafe") == "f00dcafe|f00dcafe"
    assert resolved(root, TAG="auto") == f"{head(root)}|auto → {head(root)}"


def test_none_names_the_images_latest(tmp_path: Path) -> None:
    assert resolved(repo(tmp_path, "REGISTRY=example\nTAG=none\n")) == "latest|none → latest"


@pytest.mark.parametrize("tag", ["bad tag", "-leading-dash", ".dot", "a/b", "x" * 129])
def test_an_invalid_tag_stops_every_verb(tmp_path: Path, tag: str) -> None:
    result = run(repo(tmp_path), "require_env; echo reached", TAG=tag)
    assert result.returncode == 1
    assert "reached" not in result.stdout
    assert "is not a Docker image tag; use dev, auto, none, a commit or a version" in result.stderr


def test_auto_outside_a_git_checkout_is_an_error(tmp_path: Path) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n", commit=False)
    result = run(root, "require_env; echo reached")
    assert result.returncode == 1
    assert "reached" not in result.stdout
    assert "has no git commit" in result.stderr


def test_a_nested_ctl_resolves_auto_again_at_its_own_commit(tmp_path: Path) -> None:
    root = repo(tmp_path, "REGISTRY=example\nTAG=auto\n")
    first = head(root)
    body = ('require_env; git commit -q --allow-empty -m next; '
            'bash -c \'source "$COMMON/_lib.sh"; cd "$CTL_ROOT"; require_env; printf "%s\\n" "$TAG"\'')
    result = run(root, body)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == head(root) != first


def test_an_unset_tag_is_left_alone(tmp_path: Path) -> None:
    assert resolved(repo(tmp_path, "REGISTRY=example\n")) == "|not set"


def test_soft_loading_names_a_bad_tag_and_goes_on(tmp_path: Path) -> None:
    result = run(repo(tmp_path), "load_env_soft; echo reached", TAG="bad tag")
    assert result.returncode == 0
    assert "reached" in result.stdout
    assert "is not a Docker image tag" in result.stderr
