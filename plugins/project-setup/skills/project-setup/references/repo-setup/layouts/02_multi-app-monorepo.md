# Layout 02 — multi-app monorepo

One repo, 2+ runnable apps of any mix — backends, frontends, or both. The number of backends and frontends is a **parameter**, not a separate layout: "1be+1fe", "two backends in different languages", "four frontends sharing a UI package", and "a mesh of small services" are all points on one spectrum. Start from the canonical case below and scale the relevant axis.

## When it fits

- One repo, one team, one (mostly) coordinated release cadence.
- 2+ apps that share infra (postgres + redis), tooling, and a `ctl` dispatcher.
- Contrast: a single runnable app → **Layout 01** (`references/repo-setup/layouts/01_single-app.md`). Apps that ship and release independently, or another repo that depends on this one → **Layout 03** (`references/repo-setup/layouts/03_polyrepo-with-aggregator.md`).

## Canonical tree (1 backend + 1 frontend)

The common product case and the worked example everyone starts from. One backend, one frontend, shared infra, one release cadence.

```
my-app/
├── .env                            # shared backend/infra vars only (gitignored)
├── .env.example                    # the contract (committed)
├── .env.production                 # optional, compose env_file for prod
├── .mise.toml                      # runtime contract
├── ctl                             # single dispatcher
├── docker/                         # compose mechanics → runtime/docker-overview.md
│   ├── compose.yaml                # base — the whole stack, NO profiles, no host ports
│   ├── compose.data.yaml           # standalone config (ctl up data): just the data layer
│   ├── compose.prod.yaml           # standalone config (ctl up prod): image tags, limits, .env.production
│   └── compose.m.<modifier>.yaml   # one per .m. modifier: expose (nginx) / expose_data (DB) / expose_all / traefik
├── scripts/                        # subscripts the dispatcher calls
│   ├── db-init.sh
│   ├── check-env.sh
│   └── …
├── apps/
│   ├── backend/                    # name is free: api / backend / …
│   │   ├── pyproject.toml + uv.lock
│   │   ├── config.yaml             # per-service; reads root .env via ${VAR}
│   │   ├── config.local.yaml       # gitignored override
│   │   ├── alembic/                # env.py + versions/ + alembic.ini
│   │   ├── app/                    # ← FLAT — run-service, no src/
│   │   │   ├── main.py
│   │   │   ├── api/  core/  models/  …
│   │   ├── tests/
│   │   ├── Dockerfile
│   │   └── README.md               # this backend's host dev loop
│   └── frontend/                   # name is free: web / frontend / …
│       ├── package.json + bun.lockb
│       ├── .env / .env.example     # ← frontend's OWN env (VITE_* only)
│       ├── config.yaml             # build/dev metadata (optional)
│       ├── vite.config.ts          # proxies /api/* in dev
│       ├── tailwind.config.ts
│       ├── tsconfig.json
│       ├── src/                    # ← src/ — bundler convention
│       │   ├── styles/
│       │   │   ├── tokens.css      # ← single source of design tokens
│       │   │   ├── globals.css
│       │   │   └── elements.css
│       │   ├── components/  lib/  pages/
│       ├── Dockerfile
│       └── README.md               # this frontend's host dev loop
├── infra/                          # CONFIG only (not data)
│   ├── nginx/nginx.conf            # routes /api/* to backend in prod
│   ├── postgres/init/01_extensions.sql
│   └── traefik/dynamic.yaml        # reference — only if Traefik is in scope
├── data/                           # bind-mount targets, gitignored except .gitkeep
│   ├── postgres/pgdata/.gitkeep    # nested for postgres-empty-dir requirement
│   └── redis/data/.gitkeep
├── docs/                           # documentation-template via /docs-init
├── .claude/                        # empty initially
├── CLAUDE.md
├── README.md
└── LICENSE
```

`ctl dev` is the host dev loop: auto-ups the data core (postgres + redis, with ports), installs deps (`uv sync`, `bun install`), then runs the apps on the host (uvicorn `--reload`, `bun dev`, optional nginx) in the foreground. `ctl up data` brings up just the data layer in containers; `ctl up` runs the whole stack, `ctl up prod` the production stack. Migrations run explicitly via `ctl migrate {up|down|new "<msg>"}`, never silently. See the cross-cutting refs below for env split, compose overlays, and the dispatcher contract.

## Scaling: more than one backend

When you add a second backend with a **distinct responsibility** — usually a different language (Python control plane + Rust data plane) or different performance/lifecycle needs — give each its own folder under `apps/`. Each owns its `app/` (or `crates/`), `config.yaml`, `Dockerfile`, and README; the `.mise.toml` carries every toolchain.

```
apps/
├── backend-python/   pyproject.toml + uv.lock, alembic/, app/   ← owns DDL
├── backend-rust/     Cargo.toml + rust-toolchain.toml, crates/, .sqlx/
└── frontend/         (optional, same shape as canonical)
```

The genuinely-unique guidance here is **coordination**: when two backends share state, **one owns the schema and the other consumes it.** Pick the DDL owner explicitly and document it; the non-owner reads the migrated schema and never writes DDL. Coordination goes over a shared transport — Postgres (LISTEN/NOTIFY), Redis (pub/sub, streams), or HTTP — not concurrent writes to the same tables. The `ctl` dispatcher should enforce ordering: e.g. `migrate up → sqlx prepare --check → cargo build`, failing locally on drift. Don't forget `rust-toolchain.toml` for reproducibility.

For env-var namespacing across services (`PYTHON_PORT`, `RUST_PORT`, shared `DATABASE_URL`/`REDIS_URL`), see `references/repo-setup/env-and-config/per-service-config.md` and `.../env-precedence.md`. Each backend gets its own service in `compose.yaml` with its folder as build context — see `references/repo-setup/runtime/docker-overview.md`.

## Scaling: more than one frontend

When 2+ frontends **share code** (components, hooks, types, API clients, design tokens) — main app + admin + public-share + realtime collab — promote the shared code into `packages/` and adopt a JS workspace tool (pnpm + turborepo by default; bun workspaces are a viable alternative).

```
package.json                # workspace root
pnpm-workspace.yaml
turbo.json                  # globalEnv lists every cache-busting VITE_* var
apps/
├── web/  admin/  space/  live/   # each: own package.json + VITE_* .env + Dockerfile
└── api/                          # backends still live under apps/ too
packages/
├── ui/  styles/  types/          # ← shared UI, the single tokens.css, TS types
├── tailwind-config/  typescript-config/  eslint-config/
├── hooks/  services/  utils/
```

If frontends don't actually share code, don't introduce workspaces — just use the canonical layout twice. Once you cross into needing them, **delegate the detail** to `references/architecture/frontend/multi-frontend-workspaces.md` (pnpm/turbo setup, `turbo.json` `globalEnv`, per-app env isolation) and `references/architecture/frontend/shared-ui-package.md` (the `packages/ui` + `packages/styles` tokens contract). Those refs are the source of truth; this section only tells you when to reach for them.

## Scaling: many services / mesh

At the high end, 3+ small backends each want their own service boundary — distinct schema, own migration tool, own `Dockerfile`, routing prefix per service in nginx (`/api/auth/*`, `/api/billing/*`), and per-service env namespacing (`AUTH_DATABASE_URL`, `BILLING_DATABASE_URL`). The hard rule: **no shared database tables between services** — cross-service reads are API calls, not JOINs. Shared transport concerns (auth, tracing, clients) live in `packages/`.

This is still the same monorepo spectrum, not a new kind. The signal you've outgrown it: services genuinely start releasing on **independent cadences** → split to polyrepo (**Layout 03**, `references/repo-setup/layouts/03_polyrepo-with-aggregator.md`). If orchestration across many services/repos becomes the main job → **Layout 05** (`references/repo-setup/layouts/05_infra-orchestrator.md`). If "independent cadence" is aspirational rather than real, stay here.

## Cross-cutting conventions

These are shared across every variant above; don't restate them, follow the refs:

- **Env precedence & split** — root `.env` is shared backend/infra only; frontends carry their own `VITE_*` `.env`. See `references/repo-setup/env-and-config/env-precedence.md` and `.../frontend-env-isolation.md`.
- **Per-service config** — each service has its own `config.yaml` reading root `.env` via `${VAR}`, with a gitignored `config.local.yaml`. See `references/repo-setup/env-and-config/per-service-config.md`.
- **Docker structure** — profile-less `compose.yaml` (the whole stack) plus standalone configs (`data`, `prod`) and stackable `.m.` modifiers (`expose`/`expose_data`/`expose_all`/`traefik`). See `references/repo-setup/runtime/docker-overview.md`.
- **`ctl` dispatcher** — single entry point: `ctl dev` (host) + `ctl up [config] [--modifier "a,b"]` (interactive: pick → plan → confirm) + migrate/test/clean. See `references/repo-setup/runtime/script-overview.md` (model) and `.../script-usage.md` (commands).
- **Production serving** — gunicorn + uvicorn workers with recycling behind nginx; readiness/liveness, graceful shutdown, migrations-on-deploy. See `references/architecture/production/app-server-and-workers.md` and `.../production-readiness.md`.

## Anti-patterns

- **Microservice envy** — splitting backends without a clear coordination boundary, or for a small, tightly-coupled team. Use one backend until a second has a distinct responsibility.
- **Two DDL owners** — letting more than one backend write migrations against shared schema. Pick one owner; the rest consume.
- **Shared tables across mesh services** — reaching into another service's schema with a JOIN instead of an API call.
- **Sharing config via symlinks** — each service gets its own `config.yaml`, all reading the same root `.env`.
- **Workspaces with nothing to share** — introducing pnpm/turbo for two frontends that don't share code.
- **Tokens bundled per app** — duplicating `tokens.css` instead of a single shared `packages/styles`; one app's `tailwind.config` drifting from the shared config.
- **Forgetting a `VITE_*` in `turbo.json` `globalEnv`** — produces stale, mis-built caches.
- **Aspirational independence** — adopting mesh/polyrepo boundaries before independent release cadences actually exist.
- **Missing `rust-toolchain.toml`** — Rust workspaces need it for reproducibility.

## See also

- `references/repo-setup/layouts/01_single-app.md` — one runnable app (step down)
- `references/repo-setup/layouts/03_polyrepo-with-aggregator.md` — independent release cadences (step up)
- `references/repo-setup/layouts/04_ml-project.md`, `.../layouts/05_infra-orchestrator.md`, `.../layouts/06_embeddable-package-and-reference-host.md`
- `references/architecture/frontend/multi-frontend-workspaces.md`, `references/architecture/frontend/shared-ui-package.md`
- `references/repo-setup/env-and-config/`, `references/repo-setup/runtime/` (start at `overview.md`), `references/architecture/production/`
