"""Shared pytest setup for the ctl tooling tests."""

import atexit
import os
import shutil
import tempfile
from pathlib import Path

# The tools the shipped shell code runs for real in these tests.
REAL_TOOLS = ("jq",)


def is_shim(path: str) -> bool:
    return f"{os.sep}shims{os.sep}" in path


def real_tool(name: str) -> Path | None:
    """The first executable named <name> on PATH that is no version-manager shim, else the newest
    mise install of it; None when neither exists."""
    for folder in os.environ["PATH"].split(os.pathsep):
        candidate = Path(folder, name)
        if folder and not is_shim(str(candidate)) and candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    data = Path(os.environ.get("MISE_DATA_DIR") or Path.home() / ".local/share/mise")
    for candidate in sorted(data.glob(f"installs/{name}/*/{name}"), reverse=True):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def pytest_configure() -> None:
    # Most tests replace HOME with a temporary folder. A mise shim then cannot find the user's mise
    # configuration and refuses to run, so a test would fail on the machine, not on the code. Each
    # shimmed tool is linked into a private folder put first on PATH, so no other tool changes. Every
    # test builds its PATH from this process's PATH.
    real = {}
    for name in REAL_TOOLS:
        found = shutil.which(name)
        if found and is_shim(found) and (path := real_tool(name)):
            real[name] = path
    if not real:
        return
    links = Path(tempfile.mkdtemp(prefix="ctl-tests-tools-"))
    atexit.register(shutil.rmtree, links, ignore_errors=True)
    for name, path in real.items():
        (links / name).symlink_to(path)
    os.environ["PATH"] = f"{links}{os.pathsep}{os.environ['PATH']}"
