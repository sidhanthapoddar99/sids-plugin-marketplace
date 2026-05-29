# Adapting the scripts off the recommended defaults

The `ctl` + `scripts/` toolkit is a **template, not a fixed spec** (see `script-overview.md`). The shipped Python+Node workers call four of these defaults — **mise, docker, uv, bun** — and all four are swappable. They're the stack-specific slice of a wider *recommended toolchain* (below); each is a sane modern default, never a lock-in. This doc is what to do when the user **explicitly opts out** of one: what the tool buys, what breaks without it, and exactly which `.sh` lines to edit.

**You edit the generated project's copy — never expect the shipped snippet to change.** The command *surface* (`ctl dev`, `ctl up`, …) and `_lib.sh` (colors, help, discovery) stay constant; only the tool-invoking lines inside the workers change. Keep the contract stable even when the implementation swaps tools.

| Tool | What it buys | Used by | Highly recommended because |
|---|---|---|---|
| **mise** | version pinning (`.mise.toml`) + project-scoped PATH (bare `ctl`) | `dev-host.sh` guard, `manage-status.sh` runtimes | reproducible toolchains; one entrypoint callable bare |
| **docker** | the whole container stack + `ctl dev`'s data core | every `docker-*`, `ctl up`/`dev` | prod-like parity; one-command data layer |
| **uv** (`uv sync`) | in-tree `.venv` from `pyproject.toml` + `uv.lock` | `manage-setup.sh`, `dev-host.sh`, `dev-migrate.sh`, `dev-test.sh` | fast, lockfile-reproducible app deps |
| **bun** | node deps + dev server + build | `manage-setup.sh`, `dev-host.sh`, `docker-build.sh`, `dev-test.sh` | fast, single-tool node workflow |

### The wider toolchain — recommended, never required

The four above are what the **shipped** workers invoke, because the template targets a Python + Node stack. The recommended toolchain is broader; pick what the project's languages actually need, and treat every cell as a swappable default:

| Layer | Recommended default | Pinned by | Swap to |
|---|---|---|---|
| Version manager | **mise** | — | asdf, nvm + pyenv, system installs |
| Python | **uv** (apps) · **uvenv** (ML / named-global) | mise | venv·pip, poetry, pdm, conda |
| Node | **bun** | mise | pnpm, npm, yarn |
| Rust | **cargo** (+ `rust-toolchain.toml`) | mise | system rustup |
| Go | the **`go`** toolchain | mise | system go |
| Containers | **docker** compose | — | podman, native services |

**mise is the through-line** — it pins *all* of these runtimes (`python`, `node`, `rust`, `go`, java, ruby; see `mise.md`). Adding a Rust or Go service is the same edit pattern as everything below: the worker calls `cargo build` / `go build` on the line where the Python/Node workers call `uv` / `bun`. "Highly recommended" means good defaults out of the box — it never means mandatory; any cell can be hardcoded to the project's tool of choice.

## No mise

mise isn't intrinsically required — `./ctl` runs without it. You lose bare `ctl` and version pinning. Supply python/node another way (system, `asdf` via `.tool-versions`, `nvm` via `.nvmrc`) and ensure `uv`/`bun` are on PATH.

- Call **`./ctl`** instead of `ctl` (or add the repo root to PATH yourself).
- `dev-host.sh`: `require_tools mise docker` → `require_tools docker`.
- `manage-status.sh`: in the `runtimes` step, change the missing-mise branch from `err …; rc=1` to a `warn` (or delete the mise block); the `mise current` line becomes a no-op.
- **Note:** `uvenv` (below) is built on mise+uv — dropping mise rules out uvenv too. Use `uv` or `venv` directly instead.

## No docker

Affects **all** `docker-*` commands (`up`/`build`/`clean`/`health`/`shell`) plus `ctl dev`'s data-core bring-up. Run Postgres/Redis natively (system service, Homebrew, or a managed instance) and point the apps at them via `.env` (`DATABASE_URL`, `REDIS_URL`).

- `dev-host.sh`: delete the `dc -f "$DOCKER_DIR/compose.m.expose.yaml" up -d "${DATA_SVCS[@]}"` line and the `wait_healthy …` line — the data core is now external. `require_tools mise docker` → `require_tools mise`.
- `manage-status.sh`: replace the `docker` step and the `health_table` call with native reachability checks — e.g. `pg_isready -h localhost` and `redis-cli ping`.
- `_lib.sh`: `dc()`, `svc_health`, `wait_healthy` are docker-specific; leave them unused or adapt to the native services.
- `ctl up`/`down`/etc. have no meaning without containers — drop those routes from `ctl`, or keep them for environments that do have docker.

## Python env — `uv sync` (default) vs the alternatives

The default is **in-tree `uv sync`** (`.venv` from `pyproject.toml` + `uv.lock`) — the **app** pattern (`references/architecture/backend/pyproject-uv-sync-for-apps.md`). Swap per project:

**uvenv** — mise+uv named **global** venvs, conda-style, activate-from-anywhere; the **ML / `requirements.txt`** pattern (`references/architecture/backend/requirements-uvenv-for-ml.md`). Still needs mise + uv (`uvenv doctor` verifies). uvenv installs into a venv (no lockfile sync), so it pairs with `requirements.txt`, not `uv.lock`. Its operating manual ships alongside this skill — project-setup declares `uvenv` as a plugin dependency, so the full command grammar is on hand whenever `uvenv` comes up.

```bash
# manage-setup.sh — replace `uv sync`:
uvenv create --python=3.13 -y -l ./.venv          # in-tree, OR  -n <project>  for a named global env
uvenv exec ./.venv -- uv pip install -r requirements.txt
# dev-host.sh / dev-migrate.sh / dev-test.sh — replace each `uv run <cmd>` with run-without-activating:
uvenv exec ./.venv -- uvicorn app.main:app --reload --port "${PYTHON_PORT:-8000}"
```

**plain venv + pip** — `python -m venv .venv && .venv/bin/pip install -e .` (or `-r requirements.txt`); run via `.venv/bin/<cmd>`.
**poetry / pdm** — `poetry install`; replace `uv run <cmd>` with `poetry run <cmd>`.
**conda** — `conda env create -f environment.yml`; replace `uv run <cmd>` with `conda run -n <env> <cmd>`.

Lines to edit in all cases: the `uv sync` in `manage-setup.sh`, and every `uv run …` in `dev-host.sh`, `dev-migrate.sh`, `dev-test.sh`.

## Node env — bun (default) vs pnpm / npm / yarn

| Default (`bun`) | pnpm | npm | edit in |
|---|---|---|---|
| `bun install` | `pnpm install` | `npm ci` | `manage-setup.sh` |
| `bun dev` | `pnpm dev` | `npm run dev` | `dev-host.sh` |
| `bun run build` | `pnpm build` | `npm run build` | `docker-build.sh` |
| `bun test` | `pnpm test` | `npm test` | `dev-test.sh` |

## Local-env setup (recap)

`ctl setup` installs deps (`uv sync` + `bun install`); `ctl status` warns if `apps/backend/.venv` / `apps/frontend/node_modules` are missing. If you swap either toolchain above, update those two `manage-setup.sh` lines **and** the `deps` check in `manage-status.sh` so the doctor still tells the truth.

## See also

- `script-overview.md` — the toolkit model + the `<category>-<name>.sh` convention
- `script-usage.md` — command surface, dispatcher skeleton, worked bodies, how to modify
- `mise.md` — the version contract + bare-name PATH mise provides
- `references/architecture/backend/pyproject-uv-sync-for-apps.md` · `.../requirements-uvenv-for-ml.md` — the app vs ML Python split
