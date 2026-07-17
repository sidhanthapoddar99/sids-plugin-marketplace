# Layout 02 — multi-app monorepo

One repo, 2+ runnable apps of any mix — backends, frontends, or both. The number of backends and frontends is a **parameter**, not a separate layout: "1be+1fe", "two backends in different languages", "four frontends sharing a UI package", and "a mesh of small services" are all points on one spectrum. Start from the canonical case below and scale the relevant axis. This file owns the multi-app **repo shape**, the backend/frontend scaling spectrum, the mesh end, and the core-vs-BFF axis. How `apps/` is *arranged* (flat / plane-grouped / hybrid) is the grouping-topology decision, owned separately and linked below.

## When it fits

- One repo, one team, one (mostly) coordinated release cadence.
- 2+ apps that share infra (postgres + redis), tooling, and a `ctl` dispatcher.
- Contrast: a single runnable app → **Layout 01** (`references/2-repo/layouts/01_single-app.md`). Apps that ship and release independently, or another repo that depends on this one → **Layout 03** (`references/2-repo/layouts/03_polyrepo-aggregator.md`).

## Canonical tree (1 backend + 1 frontend)

The common product case and the worked example everyone starts from. One backend, one frontend, shared infra, one release cadence.

```
my-app/
├── .env                            # shared backend/infra vars only (gitignored)
├── .env.example                    # the contract (committed)
├── .env.production                 # optional, compose env_file for prod
├── .mise.toml                      # runtime contract
├── ctl                             # single dispatcher
├── docker/                         # compose mechanics → references/2-repo/runtime/docker-overview.md
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
│   │   ├── app/                    # ← FLAT run-service — skeleton owned by references/3-app/backend/app-skeleton.md
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
│       ├── src/                    # ← src/ skeleton (styles/tokens.css, components, lib, pages) owned by references/3-app/frontend/app-skeleton.md + references/3-app/frontend/tokens-setup.md
│       ├── Dockerfile
│       └── README.md               # this frontend's host dev loop
├── infra/                          # CONFIG only (not data)
│   ├── nginx/nginx.conf            # routes /api/* to backend in prod
│   ├── postgres/init/01_extensions.sql
│   └── traefik/dynamic.yaml        # reference — only if Traefik is in scope
├── data/                           # bind-mount targets, gitignored except .gitkeep
│   ├── postgres/pgdata/.gitkeep    # nested for postgres-empty-dir requirement
│   └── redis/data/.gitkeep
├── docs/                           # docs slot — /agent-ks-init (references/1-ecosystem/docs-placement.md)
├── .claude/                        # empty initially
├── CLAUDE.md
├── README.md
└── LICENSE
```

`ctl dev` is the host dev loop (data core in containers, apps on the host with hot reload); `ctl up [config]` runs the containerised scenarios (`data`, `prod`); `ctl migrate` runs migrations explicitly. The dispatcher contract, compose axes, and env split are the cross-cutting refs below.

## Grouping topology — how `apps/` is arranged

The tree above lists apps **flat** under `apps/`. Flat is one of three named topologies (flat / plane-grouped / hybrid); which one fits, the workspace-rooting and package-placement rules, and tripwire T1 (a flat `apps/` hiding planes) are all owned by `references/2-repo/grouping-topology.md`. Pick a topology explicitly there and record it in the project CLAUDE.md.

## Scaling: more than one backend

When you add a second backend with a **distinct responsibility** — usually a different language (Python control plane + Rust data plane) or different performance/lifecycle needs — give each its own folder under `apps/`. Each owns its `app/` (or `crates/`), `config.yaml`, `Dockerfile`, and README; the `.mise.toml` carries every toolchain.

```
apps/
├── backend-python/   pyproject.toml + uv.lock, alembic/, app/   ← owns DDL (single-writer case; two writers → neutral apps/db, see migrations.md)
├── backend-rust/     Cargo.toml + rust-toolchain.toml, crates/, .sqlx/
└── frontend/         (optional, same shape as canonical)
```

The genuinely-unique guidance here is **coordination** when two backends share one DB: DDL gets a single owner and coordination goes over a shared transport — the ownership rules and the neutral `apps/db` escalation are owned by `references/3-app/backend/two-plane-split.md` (run model: `references/3-app/backend/migrations.md`); the `migrate → sqlx prepare --check → build` ordering `ctl` enforces is owned by `references/3-app/backend/raw-sql-recipe.md`. Don't forget `rust-toolchain.toml` for reproducibility.

For env-var namespacing across services (`PYTHON_PORT`, `RUST_PORT`, shared `DATABASE_URL`/`REDIS_URL`), see `references/2-repo/env-and-config/per-service-config.md` and `.../env-precedence.md`. Each backend gets its own service in `compose.yaml` with its folder as build context — see `references/2-repo/runtime/docker-overview.md`.

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

If frontends don't actually share code, don't introduce workspaces — just use the canonical layout twice. Once you cross into needing them, **delegate the detail** to `references/3-app/frontend/workspaces-mechanics.md` (pnpm/turbo setup, `turbo.json` `globalEnv`, per-app env isolation) and `references/3-app/frontend/shared-packages.md` (the `packages/ui` + `packages/styles` tokens contract). Those refs are the source of truth; this section only tells you when to reach for them. Where the workspace and its packages *sit* is the grouping-topology decision — see `references/2-repo/grouping-topology.md`.

## Frontend ↔ backend relationship — core backend vs BFF

Orthogonal to counts and topology, name which way the contract gravity points — it changes naming and where API design starts, so ask it at bootstrap:

- **Core backend** (default): the backend is the product's engine; the frontend is one consumer among possible others (CLI, integrations, public API). APIs are designed domain-first; the frontend's `api/` layer adapts to them. Name it `api`/`backend`.
- **BFF (backend-for-frontend)**: the backend exists to serve this frontend — aggregation, session, proxying to external/upstream services. The contract is designed screen-first; the backend mirrors frontend needs. Name it `bff` (or keep `api` and record the role). A reference host's optional backend in Layout 06 is typically a BFF.
- **No backend here**: the frontend talks to an external/hosted API — then this repo may actually be Layout 01 (lone frontend) with the external contract documented in `src/api/`.

Either way the routing contract is unchanged — everything under `/api/*` behind the same proxy pair (`references/2-repo/deployment/proxy-and-exposure.md`).

## Scaling: many services / mesh

At the high end, 3+ small backends each want their own service boundary — distinct schema, own migration tool, own `Dockerfile`, routing prefix per service in nginx (`/api/auth/*`, `/api/billing/*`), and per-service env namespacing (`AUTH_DATABASE_URL`, `BILLING_DATABASE_URL`). The hard rule: **no shared database tables between services** — cross-service reads are API calls, not JOINs. Shared transport concerns (auth, tracing, clients) live in `packages/`.

This is still the same monorepo spectrum, not a new kind. The signal you've outgrown it: services genuinely start releasing on **independent cadences** → split to polyrepo (**Layout 03**, `references/2-repo/layouts/03_polyrepo-aggregator.md`) — the mono-vs-poly call (incl. why aspirational independence doesn't count) is owned by `references/1-ecosystem/repo-boundaries.md`. If orchestration across many services/repos becomes the main job → **Layout 05** (`references/2-repo/layouts/05_infra-orchestrator.md`).

## Cross-cutting conventions

These are shared across every variant above; don't restate them, follow the refs:

- **Env precedence & split** — root `.env` is shared backend/infra only; frontends carry their own `VITE_*` `.env`. See `references/2-repo/env-and-config/env-precedence.md` and `.../frontend-env-isolation.md`.
- **Per-service config** — each service has its own `config.yaml` reading root `.env` via `${VAR}`, with a gitignored `config.local.yaml`. See `references/2-repo/env-and-config/per-service-config.md`.
- **Docker structure** — profile-less `compose.yaml` (the whole stack) plus standalone configs (`data`, `prod`) and stackable `.m.` modifiers (`expose`/`expose_data`/`expose_all`/`traefik`). See `references/2-repo/runtime/docker-overview.md`.
- **`ctl` dispatcher** — single entry point: `ctl dev` (host) + `ctl up [config] [--modifier "a,b"]` (interactive: pick → plan → confirm) + migrate/test/clean. See `references/2-repo/runtime/script-overview.md` (model) and `.../script-usage.md` (commands).
- **Production serving** — gunicorn + uvicorn workers with recycling behind nginx; readiness/liveness, graceful shutdown, migrations-on-deploy. See `references/3-app/backend/serving.md` (worker model) and `references/2-repo/deployment/production-readiness.md` (readiness/limits/migrations-on-deploy).

## Anti-patterns

- **Microservice envy** — splitting backends without a clear coordination boundary, or for a small, tightly-coupled team. Use one backend until a second has a distinct responsibility.
- **Two DDL owners** — more than one backend writing migrations against shared schema (owned by `references/3-app/backend/two-plane-split.md`).
- **Shared tables across mesh services** — reaching into another service's schema with a JOIN instead of an API call.
- **Sharing config via symlinks** — each service gets its own `config.yaml`, all reading the same root `.env`.
- **Workspaces with nothing to share** — introducing pnpm/turbo for two frontends that don't share code.
- **Aspirational independence** — adopting mesh/polyrepo boundaries before independent release cadences actually exist (`references/1-ecosystem/repo-boundaries.md`).

## See also

- `references/2-repo/layouts/01_single-app.md` — one runnable app (step down)
- `references/2-repo/layouts/03_polyrepo-aggregator.md` — independent release cadences (step up)
- `references/2-repo/layouts/04_ml-project.md`, `.../05_infra-orchestrator.md`, `.../06_embeddable-package.md`
- `references/2-repo/grouping-topology.md` — flat / plane-grouped / hybrid, workspace rooting, package placement (T1)
- `references/2-repo/root-and-hygiene.md` — root contract and gitignore
- `references/3-app/backend/two-plane-split.md` — separate admin/user backends + the `apps/db` migrations owner
- `references/3-app/frontend/workspaces-mechanics.md`, `references/3-app/frontend/shared-packages.md`
- `references/3-app/frontend/app-skeleton.md`, `references/3-app/backend/domain-grouping.md` — what's *inside* each app
- `references/2-repo/env-and-config/`, `references/2-repo/runtime/` (start at `overview.md`)
- `references/3-app/backend/serving.md`, `references/2-repo/deployment/production-readiness.md`
