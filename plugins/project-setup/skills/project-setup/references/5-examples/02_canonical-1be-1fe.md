# Example 02 — canonical 1 backend + 1 frontend (the flagship)

A complete, annotated worked example of **Layout 02 flat** at its most common point: one FastAPI backend, one Vite/React frontend, shared Postgres + Redis, one release cadence. Invented product: **Deskbook**, a workplace desk-and-room booking app. Every folder and file below is commented with its purpose; the closing table maps each part to the reference that owns its rule. This example is deliberately **below every subdivision tripwire** — flat backend features, no domain layer (T2), no workspace, single frontend — so it reads as the baseline everything else scales from. Nothing here is normative; the linked owner files are. Governing layout: `references/2-repo/01-layouts/02_multi-app-monorepo.md`.

## Stack at a glance

| Concern | Choice here | Owner reference |
|---|---|---|
| Repo shape | one monorepo, `apps/{backend,frontend}` | `references/2-repo/01-layouts/02_multi-app-monorepo.md` |
| Backend | FastAPI, flat `app/`, uv | `references/3-app/02-backend/00_app-skeleton.md` |
| Frontend | Vite + React 19, `src/` skeleton | `references/3-app/03-web-app/00_app-skeleton.md` |
| Data | Postgres (primary) + Redis (cache/queue) | `references/3-app/04-database/00_provisioning.md` |
| Migrations | Alembic, entrypoint-migrates | `references/3-app/04-database/01_migrations.md` |
| Runtime control | `ctl` dispatcher + `scripts/` tree | `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md` |
| Containers | profile-less `docker/` (base + configs + `.m.` modifiers) | `references/2-repo/04-docker/00_docker-overview.md` |
| Edge / routing | Vite dev proxy ↔ nginx prod pair, `/api/*` | `references/2-repo/04-docker/04_proxy-and-exposure.md` |
| Env | root `.env` (backend/infra) + frontend-local `VITE_*` | `references/2-repo/03-env-config/00_env-precedence.md` |
| Design tokens | single `tokens.css`, light/dark data-attr | `references/3-app/05-package/01_tokens-setup.md` |

## The whole repo

```
deskbook/
├── .env                            # shared BACKEND + INFRA vars only, gitignored (DATABASE_URL, REDIS_URL, secrets)
├── .env.example                    # the committed contract — every key present, values blank/placeholder
├── .env.production                 # optional; compose env_file for `ctl up prod` (real secrets injected, not via wizard)
├── .mise.toml                      # runtime contract: python 3.12, node 20, bun; project-scoped PATH makes `ctl` bare-callable
├── ctl                             # THE single dispatcher — host dev loop + container lifecycle (thin router)
├── docker/                         # all compose files live here; repo root stays compose-free
│   ├── compose.yaml                # BASE: whole stack (postgres redis backend frontend nginx), NO profiles, NO host ports
│   ├── compose.data.yaml           # CONFIG (ctl up data): standalone — just postgres + redis
│   ├── compose.prod.yaml           # CONFIG (ctl up prod): standalone — hardened stack, image tags, limits, .env.production
│   ├── compose.m.expose.yaml       # MODIFIER (--modifier expose): publish nginx (the edge) only
│   ├── compose.m.expose_data.yaml  # MODIFIER (--modifier expose_data): publish pg+redis (ctl dev applies automatically)
│   ├── compose.m.expose_all.yaml   # MODIFIER (--modifier expose_all): publish every service (debug)
│   └── compose.m.traefik.yaml      # MODIFIER (--modifier traefik): join external traefik-proxy net + labels
├── scripts/                        # the workers `ctl` routes to — grouped by category (see subtree below)
│   ├── common/                     #   sourced, not routed
│   ├── dev/                        #   host loop: host, migrate, test, lint
│   ├── container/                  #   compose lifecycle: up, build, clean, health, shell, ps
│   └── config/                     #   setup, status, check-env
├── apps/
│   ├── backend/                    # FastAPI service (name is free: api/backend/…)
│   └── frontend/                   # Vite/React app (name is free: web/frontend/…)
├── infra/                          # CONFIG only, never data — mounted read-only into containers
│   ├── nginx/nginx.conf            # prod edge: serves built frontend, routes /api/* → backend
│   ├── postgres/init/01_extensions.sql   # first-boot DDL bootstrap (CREATE EXTENSION …)
│   └── traefik/dynamic.yaml        # reference — only if Traefik is in scope
├── data/                           # bind-mount targets, gitignored except .gitkeep
│   ├── postgres/pgdata/.gitkeep    # nested one level (postgres wants an empty dir it owns)
│   └── redis/data/.gitkeep
├── docs/                           # agent-knowledge-system, scaffolded via /agent-ks-init (in-repo docs choice)
├── .claude/                        # stays empty initially — no committed settings/agents by default
├── CLAUDE.md                       # project memory: layout summary + links, deferred decisions (e.g. "T2 deferred")
├── README.md                       # root contract: the three startup paths, map of apps/
└── LICENSE
```

## Backend — `apps/backend/`

Flat `app/`, run-service layout (never installed, no `src/`). Below the domain tripwire, so features sit flat under `app/` — no `<domain>/` layer yet.

```
apps/backend/
├── pyproject.toml                  # deps + [tool.uv] package = false (run-service, not a wheel)
├── uv.lock                         # committed, reproducible dep tree
├── .venv/                          # gitignored, created by `uv sync`
├── config.yaml                     # per-service config; reads root .env via ${VAR} (one source of truth)
├── config.local.yaml               # gitignored host override
├── alembic.ini                     # script_location=alembic, prepend_sys_path=. , sqlalchemy.url left empty
├── alembic/
│   ├── env.py                      # loads db url from config.yaml with ${VAR} substitution; target_metadata = Base.metadata
│   ├── script.py.mako              # revision template
│   └── versions/                   # the migrations (timestamp_rev_slug.py)
├── app/                            # ← FLAT. Importable as `app` from service root. NO src/.
│   ├── __init__.py
│   ├── main.py                     # FastAPI app object → `app.main:app`; mounts one router per feature
│   ├── core/                       # cross-cutting plumbing: config loader, db session, redis client, security, deps
│   │   ├── config.py
│   │   ├── db.py                   # SQLAlchemy Base + async session
│   │   └── redis.py
│   ├── auth/                       # feature folder — the {router,service,repository,models}.py contract
│   │   ├── router.py               #   FastAPI endpoints (thin — delegates to service)
│   │   ├── service.py              #   business logic
│   │   ├── repository.py           #   data access (the only place SQL/ORM queries live)
│   │   └── models.py               #   ORM tables + Pydantic DTOs for THIS feature
│   ├── bookings/                   # feature: create/cancel desk & room bookings
│   ├── spaces/                     # feature: desks, rooms, floors inventory
│   └── notifications/              # feature: booking confirmations, reminders (uses redis queue)
├── tests/                          # cross-cutting fixtures; unit tests co-locate beside source
├── docker-entrypoint.sh            # runs `alembic upgrade head` on boot, then exec CMD (entrypoint-migrates)
├── gunicorn.conf.py                # prod worker config (workers, recycling, timeouts)
├── Dockerfile                      # multi-stage uv build → gunicorn; COPY app/ (flat), not src/
└── README.md                       # this backend's host dev loop (the no-docker isolation path)
```

Feature count here is 4 (`auth bookings spaces notifications`), well under the T2 threshold — so **no domain layer**, and that deferral is one line in `CLAUDE.md`. When the product's domain model settles or the list crosses the threshold, features flatten into `app/<domain>/<feature>/` — owned by `references/3-app/02-backend/01_domain-grouping.md` (T2). The `{router,service,repository,models}.py` internals, the feature-seam merge rule, and the file-subdivision tripwire (T3) are owned by `references/4-feature/01_feature-folders.md`. DTO placement (kept in each feature's `models.py`, never a shared models package) is owned by `references/4-feature/03_types-and-contracts.md`.

Migrations: single replica here, so the container migrates itself (`docker-entrypoint.sh` → `alembic upgrade head` → exec gunicorn). Multi-replica would switch to a one-shot migrate service — decision owned by `references/3-app/04-database/01_migrations.md`, recipe by `references/3-app/04-database/02_alembic-recipe.md`.

## Frontend — `apps/frontend/`

Vite + React 19, `src/` skeleton (bundler convention). Single frontend, so **no workspace** — `components/ui/` and `styles/` live locally, not in `packages/`.

```
apps/frontend/
├── package.json                    # app manifest — deps HERE, never at repo root (T10)
├── bun.lockb                       # committed lockfile
├── .env / .env.example             # ← frontend's OWN env — VITE_* ONLY (build-time, public; no secrets)
├── vite.config.ts                  # build + dev proxy: /api/* → backend (dev half of the proxy↔nginx pair)
├── tailwind.config.ts              # Tailwind preset (consumes tokens.css CSS vars)
├── tsconfig.json
├── postcss.config.cjs              # autoprefixer
├── index.html                      # Vite entry; <html data-theme="light"> — the light/dark default
├── public/                         # static assets served as-is
├── src/
│   ├── main.tsx                    # entry — imports tokens.css → globals.css → elements.css (order matters), mounts <App/>
│   ├── App.tsx                     # top-level component + router config; imports PAGES only
│   ├── layout/                     # app shells (sidebar+topbar frame, auth frame) — subdivide on outgrowth
│   ├── components/                 # common composed components (page header, empty state)
│   │   └── ui/                     #   shadcn primitives + wrappers — edit freely (copy-not-import); → packages/ui in a workspace
│   ├── features/                   # per-feature substance, folders by feature
│   │   ├── bookings/               #   booking calendar, create/cancel flows
│   │   ├── spaces/                 #   floor map, desk/room pickers
│   │   └── account/                #   profile, preferences
│   ├── pages/                      # thin route components mirroring the URL tree; compose from features/
│   ├── hooks/                      # shared hooks (feature-specific hooks live in their feature)
│   ├── api/                        # THE api access layer — all server communication; mirrors backend domains
│   ├── lib/                        # pure utilities (formatters, parsers — no React, no IO)
│   ├── stores/                     # client state (zustand); server state belongs to api/ (TanStack Query)
│   └── styles/
│       ├── tokens.css              # ← THE single source of design tokens (CSS vars, light + dark blocks)
│       ├── globals.css             # resets, base element styles
│       └── elements.css            # shared element classes
├── tests/                          # cross-cutting test setup (msw server, fixtures)
├── Dockerfile                      # multi-stage: build → nginx serve
├── nginx/nginx.conf                # optional bundled prod-stage nginx config
└── README.md                       # this frontend's host dev loop
```

The `src/` top level is a **hard skeleton** (these names, this altitude); folders appear when a thing needs them, not as empty placeholders. The skeleton, layer import-rules, and the local-vs-package reconciliation rule are owned by `references/3-app/03-web-app/00_app-skeleton.md`. What lives *inside* `api/` (endpoints, zod schemas, error normalization, query keys, domain mirroring, T6 thin pages) and how `features/` subdivides (T3) are owned by `references/4-feature/02_api-and-pages.md`. `tokens.css` contents, the light/dark `data-theme` mechanism, and shadcn/tailwind wiring are owned by `references/3-app/05-package/01_tokens-setup.md`; the primitive-first styling rules feature code lives under are owned by `references/4-feature/04_styling-discipline.md`.

## The runtime triad — `ctl` + `scripts/` + `docker/`

`ctl` is one thin router at the repo root (name is a swappable token; `ctl` here). It runs the **host dev loop** and the **container lifecycle** through two grammars — never a second wrapper.

```
scripts/
├── common/                         # shared, sourced not routed
│   ├── _lib.sh                     #   colors, indent-aware logging, dc()+discovery, health, env/tool guards
│   └── _select.sh                  #   dependency-free TUI (no fzf/gum) — sourced by _lib.sh
├── dev/                            # host-loop / development workflow
│   ├── host.sh                     #   ctl dev     — ensure data core (pg+redis) up, then run apps on host
│   ├── migrate.sh                  #   ctl migrate — alembic up/down/new/status (explicit, never silent)
│   ├── test.sh                     #   ctl test    — pytest + bun test
│   └── lint.sh                     #   ctl lint    — ruff + biome
├── container/                      # container & compose lifecycle
│   ├── up.sh                       #   ctl up      — interactive 2-axis assembly: config (replaces base) + .m. modifiers
│   ├── build.sh                    #   ctl build   — service images
│   ├── clean.sh                    #   ctl clean   — teardown + wipe volumes (asks; -y skips)
│   ├── health.sh                   #   ctl health  — one-shot health table
│   ├── shell.sh                    #   ctl shell   — psql / redis-cli / shell in a container
│   └── ps.sh                       #   ctl ps      — containers + host dev processes
└── config/                         # config management
    ├── setup.sh                    #   ctl setup   — .env wizard + secrets + data dirs + deps (project-custom)
    ├── status.sh                   #   ctl status  — read-only doctor: env·runtimes·docker·deps·health (project-custom)
    └── check-env.sh                #   helper      — .env vs .env.example schema diff
```

Everyday flow: `ctl setup` (once) → `ctl dev`. `ctl dev` auto-ups the data core (postgres + redis, with ports via `expose_data`), runs `uv sync` + `bun install`, then runs uvicorn `--reload` and `bun dev` on the host in the foreground. Containers go through `ctl up`: bare `ctl up` = the whole stack; `ctl up data` = just the data layer; `ctl up prod` = the hardened stack. There is **no `ctl prod` verb** — prod is a config. The dispatcher model (thin-router doctrine, the conformance floor, the two project-custom bodies) is owned by `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`; the exact command surface and interactive flow by `references/2-repo/05-ctl-scripts-tooling/01_script-usage.md`. The two profile-less compose axes (config replaces base; stackable `.m.` modifiers) are owned by `references/2-repo/04-docker/00_docker-overview.md`.

## Env split

- **Root `.env`** — shared backend + infra only (`DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`), gitignored; `.env.example` is the committed contract. Owned by `references/2-repo/03-env-config/00_env-precedence.md`.
- **`apps/frontend/.env`** — the frontend's own `VITE_*` vars, isolated so no server secret can leak into the client bundle. Owned by `references/2-repo/03-env-config/02_frontend-env-isolation.md`.
- **`apps/backend/config.yaml`** reads root `.env` via `${VAR}` — the per-service config pattern, owned by `references/2-repo/03-env-config/01_per-service-config.md`. The secret-by-environment matrix is owned by `references/2-repo/03-env-config/03_secrets-matrix.md`.

## Which references govern each part

| Part of this tree | Owner reference |
|---|---|
| `apps/{backend,frontend}` split, whole layout | `references/2-repo/01-layouts/02_multi-app-monorepo.md` |
| Root README, gitignore, orchestration-only root | `references/2-repo/02-root-hygiene/00_root-and-hygiene.md`, `references/2-repo/02-root-hygiene/01_readme-three-paths.md` |
| `ctl` + `scripts/` tree, conformance floor | `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`, `references/2-repo/05-ctl-scripts-tooling/01_script-usage.md` |
| `docker/` compose files (base/configs/`.m.` modifiers) | `references/2-repo/04-docker/00_docker-overview.md`, `references/2-repo/04-docker/01_docker-details.md` |
| `.mise.toml` runtime contract | `references/2-repo/06-runtime-environment/01_mise.md` |
| `.env` / `.env.example` / `config.yaml` split | `references/2-repo/03-env-config/00_env-precedence.md`, `.../01_per-service-config.md`, `.../02_frontend-env-isolation.md`, `.../03_secrets-matrix.md` |
| `infra/` vs `data/`, Postgres + Redis choice | `references/3-app/04-database/00_provisioning.md` |
| Postgres / Redis usage conventions | `references/3-app/04-database/05_postgres.md`, `references/3-app/04-database/06_redis.md` |
| `infra/nginx` ↔ Vite proxy, `/api/*` routing | `references/2-repo/04-docker/04_proxy-and-exposure.md` |
| `gunicorn.conf.py`, healthchecks, migrations-on-deploy | `references/3-app/10-deployment/00_serving.md`, `references/2-repo/04-docker/05_production-readiness.md` |
| Backend flat `app/`, uv flow, `main.py`/`core/` | `references/3-app/02-backend/00_app-skeleton.md` |
| Backend feature folders (`{router,service,repository,models}.py`) | `references/4-feature/01_feature-folders.md` |
| Domain layer deferral (T2) | `references/3-app/02-backend/01_domain-grouping.md` |
| `alembic/`, entrypoint-migrates | `references/3-app/04-database/01_migrations.md`, `references/3-app/04-database/02_alembic-recipe.md` |
| Frontend `src/` skeleton, layer rules, config files | `references/3-app/03-web-app/00_app-skeleton.md` |
| `src/api/`, `src/pages/`, `src/features/` internals (T3/T6) | `references/4-feature/02_api-and-pages.md` |
| DTO / type placement (both planes) | `references/4-feature/03_types-and-contracts.md` |
| `styles/tokens.css`, light/dark, shadcn/tailwind | `references/3-app/05-package/01_tokens-setup.md` |
| Styling discipline (primitive-first) | `references/4-feature/04_styling-discipline.md` |
| file caps (T5), extraction (T9), folders-by-feature | `references/4-feature/05_caps-and-extraction.md` |
| `docs/` in-repo choice | `references/1-ecosystem/docs-placement.md` |
| `.claude/` empty + `CLAUDE.md` template | `references/handoffs/claude-folder.md` |

## See also

- `references/5-examples/00_index.md` — how to read the examples; example ↔ layout ↔ variant map
- `references/5-examples/01_single-cli.md` — the step down (one distributable app, no compose)
- `references/5-examples/03_two-plane-monorepo.md` — the step up (plane-grouped, two backends + workspace)
- `references/2-repo/01-layouts/02_multi-app-monorepo.md` — the layout this example instantiates (scaling axes)
- `references/3-app/00_index.md` — the app-level decision index every part above serves
