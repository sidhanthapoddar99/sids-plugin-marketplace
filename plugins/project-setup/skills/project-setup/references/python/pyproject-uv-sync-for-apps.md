# Modern Python flow — `pyproject.toml` + `uv.lock` + `uv sync`

For app projects (Topology 01–06, 08). **Different from ML projects** — see `requirements-uvenv-for-ml.md`.

## The flow

```bash
# from inside apps/backend/
uv init --package <name>           # one-time, scaffolds pyproject.toml
uv add fastapi uvicorn asyncpg pydantic
uv add --dev pytest ruff mypy
uv sync                            # creates .venv, resolves, writes uv.lock
uv run uvicorn app.main:app --reload
```

## Files committed vs gitignored

| File | Committed? | Purpose |
|---|---|---|
| `pyproject.toml` | ✅ | Declared deps + project metadata |
| `uv.lock` | ✅ | Reproducible exact dep tree |
| `.venv/` | ❌ | Resolved env, host-local |
| `requirements.txt` | only if building Docker images without uv | Generated from `uv.lock` |

## `pyproject.toml` shape

```toml
[project]
name = "my-app-backend"
version = "0.1.0"
description = "API for my-app"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "asyncpg>=0.30",
    "pydantic>=2.9",
    "pyyaml>=6.0",
    "alembic>=1.13",
]

[project.optional-dependencies]
# Optional groups go here

[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24",
    "ruff>=0.6",
    "mypy>=1.11",
    "httpx>=0.27",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.uv]
package = true                 # treat as an installable package
default-groups = ["dev"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.pytest.ini_options]
pythonpath = ["src"]
asyncio_mode = "auto"
```

## Layout under `apps/backend/`

```
apps/backend/
├── pyproject.toml
├── uv.lock
├── .venv/                    # gitignored, created by uv sync
├── config.yaml
├── config.local.yaml         # gitignored
├── alembic/
│   ├── env.py
│   ├── versions/
│   └── alembic.ini
├── src/
│   └── <package_name>/       # the actual code, importable as <package_name>
│       ├── __init__.py
│       ├── main.py
│       └── …
├── tests/
└── Dockerfile
```

`src/<package_name>/` is the **src-layout** Python style. Tests import the installed package, not in-tree code. Catches accidental "works in dev because of cwd, broken when installed" bugs.

## Dockerfile (multi-stage with uv)

```dockerfile
FROM python:3.12-slim AS base
RUN pip install --no-cache-dir uv

FROM base AS deps
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

FROM base AS runtime
WORKDIR /app
COPY --from=deps /app/.venv /app/.venv
COPY src/ ./src/
COPY alembic/ ./alembic/
COPY alembic.ini ./
ENV PATH="/app/.venv/bin:$PATH"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Why `uv` over `pip` / `poetry` / `pipenv` / `pdm`

- **Fast** — Rust-based resolver and installer
- **Modern lockfile** — single `uv.lock`, reproducible
- **Drop-in** for pip's UX (`uv pip install`)
- **First-class Python version management** — `uv python install 3.12`
- **Pip-compatible package resolution** — works with the same wheels

## Why this is different from ML

ML repos use `requirements.txt` and uvenv global envs because:

- Deps are **broad** (huge libs that pin upper bounds for compat)
- Envs are **shared** across experiments
- Lockfile reproducibility matters less than ergonomics

App repos need:

- **Pinned** deps for reproducible deploys
- **Per-project** envs (each backend has its own .venv)
- **Lockfile** committed for CI

Different shapes, different tooling. Don't force one onto the other.

## Anti-patterns

- Committing `.venv/` — gigantic, host-specific
- Editing `uv.lock` by hand — let `uv add` / `uv sync` do it
- Mixing `pip install` and `uv add` in the same project — pick one
- Project-level `requirements.txt` when `pyproject.toml` exists — generate it for Docker only, gitignored
- Using `uv pip install` inside an app project — that bypasses lockfile; use `uv add` / `uv sync`
