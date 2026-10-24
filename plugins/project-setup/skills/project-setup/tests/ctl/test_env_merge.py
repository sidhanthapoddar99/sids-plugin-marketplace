"""`ctl setup` rebuilds `.env` in the shape of `.env.template` and keeps every value.

The tests run the real setup worker (`ctl setup env`, the same env step `ctl setup` runs) in
synthetic repositories with fixture env files. A secret-looking value is planted in each fixture,
and no test output may show it.
"""

import os
import pty
import select
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest

from test_setup_runtime import scaffold

SECRET = "s3cr3t-do-not-print"
STORAGE = "BASE_DIR=.\nDATA_DIR=${BASE_DIR}/data\nLOGS_DIR=${BASE_DIR}/logs\nBACKUP_DIR=${LOGS_DIR}/backups\n"
HEADER = "# Not in .env.template (kept by ctl setup)"

OLD_TEMPLATE = (
    "# Local settings.\n\n"
    "#################### SERVICE ADDRESSES ####################\n\n"
    "# API\n# docker: api\nAPI_HOST=localhost\nAPI_PORT=8000\n\n"
    "# Engine\nENGINE_PORT=8080\n\n"
    "# Beta API\n# Uncomment when the edge routes /beta.\n# BETA_API_PORT=\n\n"
    "#################### DATA PATHS ####################\n\n" + STORAGE
)
NEW_TEMPLATE = OLD_TEMPLATE.replace(
    "API_PORT=8000\n", "API_PORT=8000\n# the prefix the edge routes to the API\nAPI_PREFIX=/api\n"
).replace("# docker: api\n", "# docker: compose sets api\n")


def run(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {"PATH": str(root / "bin"), "HOME": str(root), "CTL_ROOT": str(root), "NO_COLOR": "1"}
    return subprocess.run(["/bin/bash", str(root / "scripts/config/setup.sh"), "env", *args], env=env,
                          capture_output=True, text=True, check=False, timeout=30, stdin=subprocess.DEVNULL)


def run_in_terminal(root: Path, answer: bytes, timeout: float = 30) -> tuple[int, str]:
    """Run `ctl setup env` with a pseudo-terminal as its terminal; type `answer` at the first prompt."""
    env = {"PATH": str(root / "bin"), "HOME": str(root), "CTL_ROOT": str(root), "NO_COLOR": "1", "TERM": "dumb"}
    pid, descriptor = pty.fork()
    if pid == 0:
        os.execve("/bin/bash", ["bash", str(root / "scripts/config/setup.sh"), "env"], env)
    output, answered, deadline = b"", False, time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([descriptor], [], [], 0.1)
            if not ready:
                continue
            try:
                chunk = os.read(descriptor, 4096)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            if not answered and b"[y/N]" in output:
                os.write(descriptor, answer)
                answered = True
        else:
            os.kill(pid, signal.SIGKILL)
    finally:
        _, status = os.waitpid(pid, 0)
        os.close(descriptor)
    return os.waitstatus_to_exitcode(status), output.decode(errors="replace").replace("\r\n", "\n")


def repo(tmp_path: Path, env: str, template: str = NEW_TEMPLATE, synced: str | None = OLD_TEMPLATE) -> Path:
    """A repository whose .env and template are given; `synced` is the template of the last run."""
    scaffold(tmp_path, template)
    (tmp_path / ".env").write_text(env)
    (tmp_path / ".env").chmod(0o600)
    if synced is not None:
        (tmp_path / ".env.template.synced").write_text(synced)
    return tmp_path


def lines(root: Path, name: str = ".env") -> list[str]:
    return (root / name).read_text().splitlines()


def assert_quiet(result: subprocess.CompletedProcess[str] | str) -> None:
    text = result if isinstance(result, str) else result.stdout + result.stderr
    assert SECRET not in text


# An .env written from OLD_TEMPLATE, then edited: values changed, a local comment added.
FILLED = OLD_TEMPLATE.replace("API_HOST=localhost\n", "# my note: the VM listens on all\nAPI_HOST=0.0.0.0\n") \
    .replace("API_PORT=8000", "API_PORT=9000")


def test_a_key_added_in_a_middle_section_lands_there_under_its_comment(tmp_path: Path) -> None:
    root = repo(tmp_path, FILLED)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    got = lines(root)
    at = got.index("API_PREFIX=/api")
    assert got[at - 2:at + 1] == ["API_PORT=9000", "# the prefix the edge routes to the API", "API_PREFIX=/api"]
    assert got.index("API_PREFIX=/api") < got.index("# Engine")
    for line in ("API_HOST=0.0.0.0", "API_PORT=9000", "ENGINE_PORT=8080", "BASE_DIR=."):
        assert got.count(line) == 1
    assert "added from the template: API_PREFIX" in result.stdout


def test_values_survive_byte_for_byte_and_take_the_template_order(tmp_path: Path) -> None:
    template = "# Group\n# one\nA=1\n# two\nB=2\n# three\nC=3\n# four\nD=4\nE=5\n" + STORAGE
    odd = {"A": 'A="quoted # not a comment"', "B": "B=x=y==z", "C": f"C={SECRET} # inline note",
           "D": "D=", "E": "E=\t spaced \t"}
    env = "\n".join([odd["E"], odd["C"], odd["A"], odd["D"], odd["B"]]) + "\n" + STORAGE
    root = repo(tmp_path, env, template, synced=template)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert_quiet(result)
    expected = template
    for key, line in odd.items():
        expected = expected.replace(f"{key}={ord(key) - 64}\n", line + "\n")
    assert (root / ".env").read_text() == expected


def test_a_local_comment_stays_with_its_key_and_a_reworded_template_comment_shows_the_new_text(tmp_path: Path) -> None:
    root = repo(tmp_path, FILLED)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    got = lines(root)
    at = got.index("API_HOST=0.0.0.0")
    assert got[at - 3:at + 1] == ["# API", "# docker: compose sets api", "# my note: the VM listens on all",
                                  "API_HOST=0.0.0.0"]
    assert "# docker: api" not in got
    assert "local comment lines kept: 1" in result.stdout


def test_a_local_comment_at_the_end_of_a_section_stays_there(tmp_path: Path) -> None:
    env = FILLED.replace("ENGINE_PORT=8080\n", "ENGINE_PORT=8080\n# end of engine notes\n")
    root = repo(tmp_path, env)
    assert run(root).returncode == 0
    got = lines(root)
    at = got.index("ENGINE_PORT=8080")
    assert got[at + 1:at + 3] == ["# end of engine notes", ""]
    assert "# docker: compose sets api" in got   # the template's change arrived around it


def test_a_key_set_where_the_template_shows_it_commented_out_takes_that_place(tmp_path: Path) -> None:
    env = FILLED.replace("# BETA_API_PORT=\n", "BETA_API_PORT=9300\n")
    root = repo(tmp_path, env)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    got = lines(root)
    assert got[got.index("BETA_API_PORT=9300") - 1] == "# Uncomment when the edge routes /beta."
    assert HEADER not in got and "# BETA_API_PORT=" not in got
    assert "# docker: compose sets api" in got


def test_a_key_only_env_has_goes_with_its_comment_to_the_last_section_and_is_named(tmp_path: Path) -> None:
    env = FILLED.replace("ENGINE_PORT=8080\n", f"ENGINE_PORT=8080\n# the old bucket\nLEGACY_BUCKET={SECRET}\n")
    root = repo(tmp_path, env)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert_quiet(result)
    got = lines(root)
    assert got[-4:] == ["", HEADER, "# the old bucket", f"LEGACY_BUCKET={SECRET}"]
    assert "kept in the last section of .env, not in .env.template: LEGACY_BUCKET" in result.stderr


def test_a_key_set_twice_stops_setup_and_changes_nothing(tmp_path: Path) -> None:
    env = FILLED + f"API_PORT={SECRET}\n"
    root = repo(tmp_path, env)
    result = run(root)
    assert result.returncode != 0
    first, second = FILLED.splitlines().index("API_PORT=9000") + 1, len(FILLED.splitlines()) + 1
    assert f".env sets a key twice: API_PORT (lines {first} and {second})" in result.stderr
    assert_quiet(result)
    assert (root / ".env").read_text() == env
    assert not (root / ".env.bak").exists()


def test_a_failed_write_leaves_env_whole_and_env_bak_holds_the_previous_file(tmp_path: Path) -> None:
    root = repo(tmp_path, FILLED)
    shim = root / "bin/mv"
    shim.unlink()
    shim.write_text(f'#!/bin/bash\n[[ ${{!#}} == .env ]] && exit 1\nexec {shutil.which("mv")} "$@"\n')
    shim.chmod(0o755)
    result = run(root)
    assert result.returncode != 0
    assert "could not write .env. It is as it was" in result.stderr
    assert (root / ".env").read_text() == FILLED
    assert (root / ".env.bak").read_text() == FILLED
    assert (root / ".env.bak").stat().st_mode & 0o777 == 0o600
    assert sorted(path.name for path in root.glob(".env*")) == [".env", ".env.bak", ".env.template",
                                                                 ".env.template.synced"]


def test_a_second_run_changes_nothing(tmp_path: Path) -> None:
    env = FILLED.replace("ENGINE_PORT=8080\n", "ENGINE_PORT=8080\n# end of engine notes\n\n# a free note\n") \
        + "# about OLD\nOLD_KEY=1\n# after old\n"
    root = repo(tmp_path, "# a note on top\n" + env)
    first = run(root)
    assert first.returncode == 0, first.stdout + first.stderr
    assert lines(root)[:2] == ["# a note on top", "# Local settings."]
    assert lines(root)[-5:] == ["", HEADER, "# about OLD", "OLD_KEY=1", "# after old"]
    merged, backup = (root / ".env").read_bytes(), (root / ".env.bak").read_bytes()
    stamp = (root / ".env").stat().st_mtime_ns
    second = run(root)
    assert second.returncode == 0, second.stdout + second.stderr
    assert (root / ".env").read_bytes() == merged and (root / ".env").stat().st_mtime_ns == stamp
    assert (root / ".env.bak").read_bytes() == backup
    assert ".env is in the shape of .env.template" in second.stdout
    assert (root / ".env").stat().st_mode & 0o777 == 0o600


def test_without_a_record_of_the_last_template_every_unknown_comment_is_kept_and_said(tmp_path: Path) -> None:
    root = repo(tmp_path, FILLED, synced=None)
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    got = lines(root)
    assert "# docker: api" in got and "# my note: the VM listens on all" in got
    assert "no record of the template it last matched" in result.stderr
    assert (root / ".env.template.synced").read_text() == NEW_TEMPLATE
    # The record now exists, so the next template change tells the two kinds of comment apart.
    (root / ".env.template").write_text(NEW_TEMPLATE.replace("# docker: compose sets api\n", ""))
    assert run(root).returncode == 0
    assert "# docker: compose sets api" not in lines(root)


def test_a_new_env_is_the_template_and_records_it(tmp_path: Path) -> None:
    scaffold(tmp_path, NEW_TEMPLATE)
    result = run(tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / ".env").read_text() == NEW_TEMPLATE
    assert (tmp_path / ".env.template.synced").read_text() == NEW_TEMPLATE
    assert not (tmp_path / ".env.bak").exists()


# ── removing keys the template lacks ──
UNLISTED = FILLED + f"\n# old flag\nOLD_FEATURE_FLAG={SECRET}\nLEGACY_S3_BUCKET={SECRET}-bucket\n"
PROMPT = "These keys are in .env but not in .env.template:\n  OLD_FEATURE_FLAG\n  LEGACY_S3_BUCKET\n"


def test_in_a_terminal_yes_removes_the_keys_and_env_bak_holds_them(tmp_path: Path) -> None:
    root = repo(tmp_path, UNLISTED)
    code, output = run_in_terminal(root, b"y\n")
    assert code == 0, output
    assert PROMPT in output and "Remove them from .env? [y/N]" in output
    assert_quiet(output)
    text = (root / ".env").read_text()
    assert "OLD_FEATURE_FLAG" not in text and "LEGACY_S3_BUCKET" not in text and "# old flag" not in text
    assert HEADER not in text
    assert (root / ".env.bak").read_text() == UNLISTED
    assert "removed from .env, not in .env.template: OLD_FEATURE_FLAG LEGACY_S3_BUCKET" in output


@pytest.mark.parametrize("answer", [b"n\n", b"\n"], ids=["no", "enter"])
def test_in_a_terminal_no_or_enter_keeps_the_keys_and_names_them(tmp_path: Path, answer: bytes) -> None:
    root = repo(tmp_path, UNLISTED)
    code, output = run_in_terminal(root, answer)
    assert code == 0, output
    assert PROMPT in output
    assert_quiet(output)
    got = lines(root)
    assert got[-4:] == [HEADER, "# old flag", f"OLD_FEATURE_FLAG={SECRET}", f"LEGACY_S3_BUCKET={SECRET}-bucket"]
    assert "kept in the last section of .env, not in .env.template: OLD_FEATURE_FLAG LEGACY_S3_BUCKET" in output


def test_with_no_terminal_nothing_asks_and_the_keys_are_kept(tmp_path: Path) -> None:
    root = repo(tmp_path, UNLISTED)
    started = time.monotonic()
    result = run(root)
    assert time.monotonic() - started < 20
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[y/N]" not in result.stdout and "These keys are in" not in result.stdout
    assert_quiet(result)
    assert f"OLD_FEATURE_FLAG={SECRET}" in lines(root)
    assert "kept in the last section of .env, not in .env.template: OLD_FEATURE_FLAG LEGACY_S3_BUCKET" in result.stderr


def test_remove_unlisted_removes_the_keys_without_asking(tmp_path: Path) -> None:
    root = repo(tmp_path, UNLISTED)
    result = run(root, "--remove-unlisted")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[y/N]" not in result.stdout
    assert_quiet(result)
    assert "OLD_FEATURE_FLAG" not in (root / ".env").read_text()
    assert (root / ".env.bak").read_text() == UNLISTED
    assert "removed from .env, not in .env.template: OLD_FEATURE_FLAG LEGACY_S3_BUCKET" in result.stdout


@pytest.mark.parametrize("args", [("--help",), ("env", "--help")], ids=["setup", "setup-env"])
def test_setup_help_shows_remove_unlisted(tmp_path: Path, args: tuple[str, ...]) -> None:
    scaffold(tmp_path, NEW_TEMPLATE)
    env = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), "CTL_ROOT": str(tmp_path), "NO_COLOR": "1"}
    result = subprocess.run(["/bin/bash", str(tmp_path / "scripts/config/setup.sh"), *args], env=env,
                            capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert "--remove-unlisted" in result.stdout
