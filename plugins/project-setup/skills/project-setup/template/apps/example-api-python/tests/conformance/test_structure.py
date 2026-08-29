"""Structure checks — unit tests whose subject is the file tree, not a function.

This is the Python shape of the model in neurasutra-editor
``apps/packages/editor/conformance/structure/``. One file holds the three parts:

  REGISTRY   the list of checks, hand-written, in order. ``test_registry_count`` pins it,
             so a check cannot be dropped silently.
  THE RUN    every check over the real tree (``app/``). Green = no violation.
  DETECTION  every check over a temp fixture tree that breaks its rule on purpose. A check
             with no red fixture is not proved to bite: on a clean tree, a check that
             returns nothing looks the same as a check that works.

Three properties make it a test and not a scan (06_testing.md, "Conformance"):
  1. the rule is a hand-written list (LAYER_ORDER, ENV_READERS), never derived from disk
  2. every check has a red fixture (``test_detection_*``)
  3. exemptions expire — a LEDGER row for a file that no longer violates is itself red

Runs under ``uv run pytest`` like any other test, so ``ctl test api`` and ``ctl gate test``
both run it. Add a check when a rule in 07_conventions.md is broken a second time.
"""

from __future__ import annotations

import ast
from dataclasses import dataclass
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parents[2] / "app"


@dataclass(frozen=True)
class Violation:
    file: Path
    line: int
    rule: str

    def __str__(self) -> str:
        return f"{self.file}:{self.line}: {self.rule}"


# ── the rules, written by hand ───────────────────────────────────────────────

# A layer imports only inward. router → service → repository → models. Across domains,
# service → service only. The order is the rule; a scan of the folders would not be.
LAYER_ORDER = ("router", "service", "repository", "models")

# The one module allowed to read the process environment (02_env.md, one loader per backend).
ENV_READERS = {"config.py"}

# LEDGER — hand-kept exemptions: {relative path: reason}. A row whose file is clean is red.
LEDGER_ENV: dict[str, str] = {}


# ── the checks ───────────────────────────────────────────────────────────────

def _py_files(root: Path):
    return sorted(p for p in root.rglob("*.py") if "__pycache__" not in p.parts)


def _imports(tree: ast.AST):
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            yield node.lineno, node.module
        elif isinstance(node, ast.Import):
            for alias in node.names:
                yield node.lineno, alias.name


def check_layer_imports(root: Path) -> list[Violation]:
    """A layer file imports only from layers after it in LAYER_ORDER; cross-domain only via service."""
    out: list[Violation] = []
    for f in _py_files(root):
        layer = f.stem
        if layer not in LAYER_ORDER:
            continue
        domain = f.parent.name
        tree = ast.parse(f.read_text(), filename=str(f))
        for line, mod in _imports(tree):
            parts = mod.split(".")
            if len(parts) < 3 or parts[0] != "app":
                continue
            target_domain, target_layer = parts[1], parts[2]
            if target_layer not in LAYER_ORDER:
                continue
            if target_domain != domain and target_layer != "service":
                out.append(Violation(f, line, f"{domain}/{layer} reaches {target_domain}/{target_layer}; across domains only service is public"))
            elif target_domain == domain and LAYER_ORDER.index(target_layer) <= LAYER_ORDER.index(layer):
                out.append(Violation(f, line, f"{layer} imports {target_layer}; imports point inward only ({' → '.join(LAYER_ORDER)})"))
    return out


def check_env_access(root: Path) -> list[Violation]:
    """os.environ / os.getenv appear only in ENV_READERS. Ledger rows must still be needed."""
    out: list[Violation] = []
    seen_dirty: set[str] = set()
    for f in _py_files(root):
        if f.name in ENV_READERS:
            continue
        rel = str(f.relative_to(root))
        tree = ast.parse(f.read_text(), filename=str(f))
        for node in ast.walk(tree):
            hit = (
                isinstance(node, ast.Attribute) and node.attr in {"environ", "getenv"}
                and isinstance(node.value, ast.Name) and node.value.id == "os"
            )
            if hit:
                seen_dirty.add(rel)
                if rel not in LEDGER_ENV:
                    out.append(Violation(f, getattr(node, "lineno", 0), "reads the environment outside config.py (one loader per backend)"))
    for rel in LEDGER_ENV:
        if rel not in seen_dirty:
            out.append(Violation(root / rel, 0, "ledger row is stale — the file no longer reads the environment; delete the row"))
    return out


# ── the registry ─────────────────────────────────────────────────────────────

REGISTRY = (
    ("layer-imports", check_layer_imports),
    ("env-access", check_env_access),
)


def test_registry_count():
    assert len(REGISTRY) == 2, "a check was added or removed — update the count and its detection test"


@pytest.mark.parametrize(("name", "check"), REGISTRY, ids=[n for n, _ in REGISTRY])
def test_structure(name, check):
    violations = check(APP)
    assert not violations, f"{name} RED:\n" + "\n".join(str(v) for v in violations)


# ── detection: each rule proved to bite on a fixture that breaks it ──────────

def _fixture(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, body in files.items():
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
    return tmp_path


def test_detection_layer_imports(tmp_path):
    root = _fixture(tmp_path, {
        "users/repository.py": "from app.users.router import r\n",       # outward
        "users/router.py": "from app.workspaces.repository import q\n",  # cross-domain, not service
        "users/service.py": "from app.workspaces.service import s\n",    # allowed
    })
    rules = [v.rule for v in check_layer_imports(root)]
    assert len(rules) == 2 and any("inward" in r for r in rules) and any("across domains" in r for r in rules)


def test_detection_env_access(tmp_path):
    root = _fixture(tmp_path, {
        "config.py": "import os\nX = os.environ['X']\n",        # the reader
        "users/service.py": "import os\nY = os.getenv('Y')\n",  # the violation
    })
    out = check_env_access(root)
    assert [str(v.file.relative_to(root)) for v in out] == ["users/service.py"]
