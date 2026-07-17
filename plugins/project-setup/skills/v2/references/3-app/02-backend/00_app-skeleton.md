# Backend skeleton — flat `app/`, the uv flow, the top-level layout

Owns three things for a backend app: **the run-service-vs-distributable layout rule** (flat `app/` vs `src/<pkg>/`), **the `pyproject.toml` + `uv.lock` + `uv sync` flow** (decision + mechanics), and **the top-level skeleton** inside `app/` (`main.py`, `core/`, feature folders). For app projects — Layout 01–03, 05. ML projects use a different flow (`references/3-app/02-backend/03_ml-python-flow.md`). Domain *grouping* (T2) and feature-folder *internals* are owned below this file — links in place.

## First decision — run-service or distributable package?

The layout differs, and it matters:

| | **Run-service** (FastAPI / Flask / worker) | **Distributable package / library / CLI** |
|---|---|---|
| Layout | **flat `app/`** | **`src/<pkg>/`** (src-layout) |
| `[tool.uv] package` | `false` (or omit) — it's run, not built | `true` — it's built into a wheel |
| Why | Launched via `uvicorn app.main:app`; never installed. `src/` would only add `PYTHONPATH` / `prepend_sys_path` plumbing for no benefit. | src-layout forces tests to import the *installed* package — catches "works because of cwd, breaks when installed" bugs |
| `pythonpath` (pytest) | `["."]` | `["src"]` |
| Examples | the backend in Layout 02; the official full-stack FastAPI template (`backend/app/`) | a published CLI, a shared library, an SDK |

**Default for a backend is the run-service column.** Only reach for src-layout when the thing is genuinely distributable. (A distributable's *repo shape* and publishing mechanics are L2 — `references/2-repo/01-layouts/06_embeddable-package.md`.)

## The flow — run-service (the common case)

```bash
# from inside the service folder (top-level ./api/ if one service, or apps/api/ if several)
uv init --bare                     # pyproject.toml without forcing a package layout
uv add fastapi "uvicorn[standard]" asyncpg pydantic pyyaml alembic
uv add --dev pytest pytest-asyncio ruff mypy httpx
uv sync                            # creates .venv, resolves, writes uv.lock
uv run uvicorn app.main:app --reload
```

Code lives in `app/` next to `pyproject.toml`; nothing is "installed" — `app.main:app` resolves because cwd is the service root.

## The flow — distributable package

```bash
uv init --package <name>           # scaffolds src/<name>/ + package metadata
uv add <runtime-deps>
uv add --dev pytest ruff mypy
uv sync
uv run <entry-point>
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

# [build-system] is only needed for a DISTRIBUTABLE package:
# [build-system]
# requires = ["hatchling"]
# build-backend = "hatchling.build"

[tool.uv]
package = false                # run-service: NOT built into a wheel.
                               # set true ONLY for a distributable package.
default-groups = ["dev"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.pytest.ini_options]
pythonpath = ["."]             # run-service: code is in ./app, importable from service root.
                               # a distributable package uses ["src"] instead.
asyncio_mode = "auto"
```

## The top-level skeleton — run-service (the default for a backend)

```
<service>/                    # top-level ./<name>/ if one service; apps/<name>/ if several
├── pyproject.toml
├── uv.lock
├── .venv/                    # gitignored, created by uv sync
├── config.yaml
├── config.local.yaml         # gitignored
├── alembic/
│   ├── env.py
│   └── versions/
├── alembic.ini
├── app/                      # ← FLAT. The code. Importable as `app` from service root.
│   ├── __init__.py
│   ├── main.py               # FastAPI app object → `app.main:app`
│   ├── core/                 # app-wide config, db session, shared deps
│   ├── <feature>/            # feature folders: {router,service,repository,models}.py
│   └── …
├── tests/
├── Dockerfile
└── README.md                 # this service's host dev loop
```

No `src/`. The service runs from its own root, so `app.main:app` resolves with no `PYTHONPATH` plumbing. This matches the official full-stack FastAPI template.

**Firm names at this altitude:** `main.py` (the app object), `core/` (app-wide config / db session / shared dependencies), and one folder per feature. **Below the feature folder the shape is owned elsewhere:** the `{router,service,repository,models}.py` contract lives in `references/4-feature/01_feature-folders.md`; when to flatten features into `app/<domain>/<feature>/` (tripwire T2) and how domains are named lives in `references/3-app/02-backend/01_domain-grouping.md`.

## The top-level skeleton — distributable package (only when it's actually shipped)

```
<pkg>/
├── pyproject.toml            # with [build-system] + [tool.uv] package = true
├── uv.lock
├── src/
│   └── <pkg>/                # src-layout — tests import the INSTALLED package
│       ├── __init__.py
│       └── …
├── tests/
└── README.md
```

`src/<pkg>/` forces clean packaging and catches "works because of cwd, breaks when installed" bugs. Use this **only** for things you build into a wheel / publish.

## Dockerfile (multi-stage with uv) — run-service

```dockerfile
FROM python:3.12-slim AS base
RUN pip install --no-cache-dir uv

FROM base AS deps
WORKDIR /srv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

FROM base AS runtime
WORKDIR /srv
COPY --from=deps /srv/.venv /srv/.venv
COPY app/ ./app/             # ← the code (flat), not src/
COPY alembic/ ./alembic/
COPY alembic.ini ./
COPY config.yaml ./
ENV PATH="/srv/.venv/bin:$PATH"
# dev uses `uvicorn --reload`; prod uses gunicorn — worker model owned by references/3-app/10-deployment/00_serving.md
CMD ["gunicorn", "app.main:app", "-c", "gunicorn.conf.py"]
```

(A distributable package's Dockerfile would `COPY src/ ./src/` and typically `uv sync` *with* `--no-install-project` dropped so the package itself installs.)

## Why `uv` over `pip` / `poetry` / `pipenv` / `pdm`

- **Fast** — Rust-based resolver and installer
- **Modern lockfile** — single `uv.lock`, reproducible
- **Drop-in** for pip's UX (`uv pip install`)
- **First-class Python version management** — `uv python install 3.12`
- **Pip-compatible package resolution** — works with the same wheels

## Why this is different from ML

ML repos use a deliberately different flow (broad `requirements.txt`, one shared uvenv env) — the ML flow + the full app-vs-ML comparison are owned by `references/3-app/02-backend/03_ml-python-flow.md`. Don't force one onto the other.

## Anti-patterns

- **src-layout for a run-service** — adds `PYTHONPATH` / `prepend_sys_path` plumbing for zero benefit. Flat `app/` for services; `src/<pkg>/` only for distributables.
- `package = true` on a backend that's never built into a wheel — it's not a package, don't pretend.
- Committing `.venv/` — gigantic, host-specific.
- Editing `uv.lock` by hand — let `uv add` / `uv sync` do it.
- Mixing `pip install` and `uv add` in the same project — pick one.
- Project-level `requirements.txt` when `pyproject.toml` exists — generate it for Docker only, gitignored.
- Using `uv pip install` inside an app project — that bypasses the lockfile; use `uv add` / `uv sync`.

## See also

- `references/3-app/02-backend/01_domain-grouping.md` — feature → domain grouping (T2), domain naming
- `references/4-feature/01_feature-folders.md` — the `{router,service,repository,models}.py` contract
- `references/3-app/04-database/01_migrations.md` — Alembic vs raw-SQL and the migration owner
- `references/3-app/10-deployment/00_serving.md` — production worker model (gunicorn CMD)
- `references/3-app/02-backend/03_ml-python-flow.md` — the ML flow this is deliberately different from
