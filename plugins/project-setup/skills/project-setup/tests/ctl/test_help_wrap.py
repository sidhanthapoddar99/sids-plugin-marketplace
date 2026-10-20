"""Help folds to the terminal's width, and a pipe gets the text as written.

The terminal tests run the real template ctl inside a pseudo-terminal of a set width, with colors on,
so `stty size </dev/tty` reads that width as it does in a person's terminal. The rule tests feed
short texts through `_help_fold` from the real shell library, line by line as `help_wrap` does.
"""

import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import termios
import time
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[2] / "template"
LIB = TEMPLATE / "scripts/common/_lib.sh"
SGR = re.compile(r"\x1b\[[0-9;]*m")


def project(tmp_path: Path) -> Path:
    root = tmp_path / "project"
    root.mkdir()
    for name in ("ctl", "scripts", "docker"):
        source = TEMPLATE / name
        (shutil.copytree if source.is_dir() else shutil.copy)(source, root / name)
    return root


def environment(root: Path) -> dict[str, str]:
    return {"PATH": os.environ["PATH"], "HOME": str(root), "TERM": "xterm-256color", "LANG": "C.UTF-8"}


def in_terminal(root: Path, columns: int, *arguments: str, timeout: float = 30) -> tuple[int, str]:
    """Run ctl with a pseudo-terminal of <columns> as its controlling terminal; return what it printed."""
    bash = shutil.which("bash")
    pid, descriptor = pty.fork()
    if pid == 0:
        fcntl.ioctl(1, termios.TIOCSWINSZ, struct.pack("HHHH", 40, columns, 0, 0))
        os.chdir(root)
        os.execve(bash, ["bash", str(root / "ctl"), *arguments], environment(root))
    output, deadline = b"", time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([descriptor], [], [], 0.1)
            if not ready:
                continue
            try:
                chunk = os.read(descriptor, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
        else:
            os.kill(pid, signal.SIGKILL)
    finally:
        _, status = os.waitpid(pid, 0)
        os.close(descriptor)
    return os.waitstatus_to_exitcode(status), output.decode().replace("\r\n", "\n")


def piped(root: Path, *arguments: str) -> str:
    result = subprocess.run(["bash", str(root / "ctl"), *arguments], env=environment(root), cwd=root,
                            capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL)
    return result.stdout


def fold(text: str, columns: int) -> list[str]:
    """Fold <text> line by line as help_wrap does in a terminal of <columns>."""
    script = 'source "$1"; while IFS= read -r line || [[ -n $line ]]; do _help_fold "$line" "$2"; done'
    result = subprocess.run(["bash", "-c", script, "bash", str(LIB), str(columns)], input=text,
                            capture_output=True, text=True, check=True, env={"PATH": os.environ["PATH"], "LANG": "C.UTF-8"})
    return result.stdout.splitlines()


@pytest.mark.parametrize("arguments", [("--help",), ("up", "--help"), ("gate", "--help")])
def test_help_in_a_narrow_terminal_fits_and_keeps_every_word(tmp_path: Path, arguments: tuple[str, ...]) -> None:
    root = project(tmp_path)
    code, output = in_terminal(root, 60, *arguments)
    assert code == 0, output
    plain = SGR.sub("", output)
    assert "\x1b[" in output, "the terminal run should be colored, so the width check covers color codes"
    assert [line for line in plain.splitlines() if len(line) > 60] == []
    # folding moves words to new lines and changes nothing else
    assert plain.split() == piped(root, *arguments).split()


def test_a_folded_row_continues_under_its_description(tmp_path: Path) -> None:
    root = project(tmp_path)
    _, output = in_terminal(root, 60, "up", "--help")
    lines = SGR.sub("", output).splitlines()
    row = next(i for i, line in enumerate(lines) if line.startswith("  --services <csv>"))
    column = lines[row].index("start only")
    assert column == 22
    assert lines[row + 1].startswith(" " * column) and lines[row + 1][column] != " "


def test_a_pipe_and_a_tiny_terminal_get_the_text_as_written(tmp_path: Path) -> None:
    root = project(tmp_path)
    text = piped(root, "up", "--help")
    assert "  --services <csv>    start only these services (comma-list). A service's depends_on chain comes with it.\n" in text
    _, output = in_terminal(root, 30, "up", "--help")
    assert SGR.sub("", output) == text


@pytest.mark.parametrize(("text", "columns", "expected"), [
    # a row continues under its text
    ("  -a, --attach    run in the foreground and stream the logs",
     40, ["  -a, --attach    run in the foreground",
          " " * 18 + "and stream the logs"]),
    # a row whose text column leaves under 20 columns puts its text on its own lines, 4 deeper
    ("  ctl up --services=api,postgres -y     # one backend and its chain only",
     50, ["  ctl up --services=api,postgres -y",
          " " * 6 + "# one backend and its chain only"]),
    # it does so even when the row fits, so rows that share a column stay alike
    ("  --a-long-option-name    yes",
     40, ["  --a-long-option-name",
          " " * 6 + "yes"]),
    # a line whose indent leaves under 20 columns moves 4 deeper than the last line that left
    # more, so a moved row's lines below move with it and keep any extra indent
    ("  --a-long-option-name    the first line of its text\n"
     + " " * 26 + "a second line, written by hand\n"
     + " " * 28 + "an indented third line\n"
     + "\n"
     + "  next  row",
     40, ["  --a-long-option-name",
          " " * 6 + "the first line of its text",
          " " * 6 + "a second line, written by hand",
          " " * 8 + "an indented third line",
          "",
          "  next  row"]),
    # the same holds for a text written by hand on the line below its term
    ("  a-term-with-its-text-below [--flag]\n"
     + " " * 30 + "its text, written on the next line",
     40, ["  a-term-with-its-text-below [--flag]",
          " " * 6 + "its text, written on the next line"]),
    # a line indented 1 or 2 columns, and no row, continues 2 deeper
    ("  ctl up [--config <name>] [+modifier…] [--services a,b] [-y]",
     45, ["  ctl up [--config <name>] [+modifier…]",
          " " * 4 + "[--services a,b] [-y]"]),
    # indented prose with a double space deep inside is no row, and folds as plain text
    ("  a long line of indented prose that has a double  space near its end here",
     40, ["  a long line of indented prose that has",
          " " * 4 + "a double  space near its end here"]),
    # a line at column 0 continues at column 0, and a gap inside the text is kept
    ("Prose at the margin keeps its margin,  even with  wide gaps inside.",
     40, ["Prose at the margin keeps its margin,",
          "even with  wide gaps inside."]),
    # a color code takes no column
    ("\x1b[1mBold\x1b[0m heading that runs a little past the edge here",
     40, ["\x1b[1mBold\x1b[0m heading that runs a little past the",
          "edge here"]),
    # a word longer than the room is never split: it runs past the edge, and the next word folds
    ("  path  /a/very/long/path/that/cannot/be/split/anywhere/at/all ok",
     40, ["  path  /a/very/long/path/that/cannot/be/split/anywhere/at/all",
          " " * 8 + "ok"]),
])
def test_fold_rules(text: str, columns: int, expected: list[str]) -> None:
    assert fold(text, columns) == expected
