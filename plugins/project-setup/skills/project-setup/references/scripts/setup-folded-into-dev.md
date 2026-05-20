# Setup folds into `./dev`

No `setup.dev.sh`, no `setup.prod.sh`, no `install.sh`. The `./dev` wrapper handles first-run setup and steady-state both.

## How `./dev` detects first run vs steady state

First-run signals (any of these missing → run setup steps):

- `.env` doesn't exist (copy from `.env.example`, exit with instructions)
- `data/postgres/pgdata` doesn't exist (create the directory tree)
- `apps/frontend/node_modules` doesn't exist (run `bun install`)
- Python `.venv` doesn't exist (run `uv sync` which creates it)
- Compose services not running (start them)

The wrapper checks each, runs the corresponding action, and proceeds to the steady-state flow.

## Skeleton

```bash
cmd_bare() {
  c_info "<PROJECT> dev"

  # ── First-run checks ────────────────────────────────────
  require_env                                    # creates .env from .env.example if missing
  require_tools                                  # mise/docker on PATH

  c_info "Ensuring data dirs exist…"
  mkdir -p data/postgres/pgdata data/redis/data

  # ── Compose: only DBs needed in dev ─────────────────────
  c_info "Bringing up postgres + redis…"
  docker compose -f docker/compose.database-only.yaml up -d
  bash scripts/wait-for-health.sh postgres redis 60

  # ── Deps: install if missing, sync if present ───────────
  if [[ ! -d apps/frontend/node_modules ]]; then
    c_info "Installing frontend deps (bun install)…"
    ( cd apps/frontend && bun install )
  fi

  c_info "Syncing python deps (uv sync)…"
  ( cd apps/backend && uv sync )

  # ── Migrations ──────────────────────────────────────────
  c_info "Applying migrations…"
  ( cd apps/backend && uv run alembic upgrade head )

  # ── Run all services ────────────────────────────────────
  c_info "Starting services on host. Ctrl-C kills all."
  # ... start backend + frontend with prefixed log streams ...
}
```

## Why not separate setup scripts?

- **One contract** — users learn `./dev` and that's it
- **Fewer states to track** — "did I run setup?" disappears; bare `./dev` is always safe
- **Discovery** — `./dev help` is the only place to look
- **CI parity** — CI runs the same `./dev` as a human; no special setup step

The plane project has `setup.dev.sh` + `setup.prod.sh` separate from a dev script. Atheneum folds both into `./dev`. **We prefer the atheneum pattern.**

## Exception: production deploy

If a project has a true deploy mode (image pull, rolling update, migration runner), a separate `./deploy` or `scripts/deploy.sh` is fine. That's a different audience and lifecycle.

For local dev, no setup scripts.

## When `./dev` setup gets long

If first-run takes 5+ minutes of compose-up + install + migrate + build, expose progress and consider:

1. **A `./dev install` subcommand** that does only the install phase — useful for "I just want deps, not to run anything"
2. **Caching** — `.dev-cache/` with timestamps; skip steps whose inputs haven't changed
3. **Parallelism** — bun install and uv sync can run in parallel

Don't split into a separate script just because it's slow. Split when there's a genuinely different audience.

## What goes in `./dev` and what doesn't

| In `./dev` | Not in `./dev` |
|---|---|
| Bring up dev databases | Bring up production stack |
| Install/sync dev deps | Build production images |
| Run migrations against dev | Run migrations against prod |
| Start dev hot-reload processes | Start production containers |
| Run local test suites | Run CI test orchestration (CI has its own steps) |
| Clean dev state | Wipe production data |

## Anti-patterns

- `setup.sh` + `start.sh` + `dev.sh` + `test.sh` at root — four contracts to remember
- README instructions like "first run `make install`, then `make dev`" — fold both
- Letting `./dev` skip setup steps silently when invariants break — fail loudly instead
- Different `./dev` shapes per branch — keep the contract stable
