# Examples index — real-world repos this plugin cites

Sid's actual projects. **Not perfect** — they evolved at different times with different constraints. They demonstrate the conventions in production, and they're the ground truth the skill should cite (not invent file paths from training data).

## atheneum — Topology 03 (multi-backend microservices)

**Location**: `~/projects/02_OpenSource/04_knowledge_management/atheneum`
**GitHub**: `https://github.com/sidhanthapoddar/atheneum`

The canonical example for:

- Python + Rust dual backend coordinating via Redis/Streams + shared Postgres
- Alembic with raw `.sql` + 3-line Python shim pattern
- Single source of truth: Python owns DDL, Rust never writes it
- `ctl` dispatcher with subcommands (`migrate`, `sqlx-prepare`, `test`, `clean`)
- Apps-on-host + DBs-in-containers dev mode
- Design tokens in `frontend/src/styles/tokens.css`
- Light + dark + glassmorphism, three font sizes
- Modularity rule: 500-line hard / 300-line soft / folders by feature

Files worth studying:

- `ctl` — the `ctl` dispatcher, well-commented
- `docker-compose.yaml` — bind-mount + nested-data-dir trick
- `CLAUDE.md` — agent brief
- `README.md` — three-path structure
- `backend-python/alembic/versions/` — raw SQL shim pattern
- `frontend/src/styles/tokens.css` — design tokens

Drifts (when migrating to current conventions):

- Compose files at root rather than in `docker/` (older convention)
- `frontend/`, `backend-python/`, `backend-rust/` at root rather than under `apps/`
- No `infra/` folder (postgres init scripts are at `scripts/postgres-init/`)

## NeuraSutra — Topology 02 (mono 1be + 1fe), with deployment-mode split

**Location**: `~/projects/06_04_NeuraSutra/neurasutra-api-management`

The canonical example for:

- Multi-file compose split by deployment mode: `docker-compose.yaml` (base), `-database.yaml` (db-only), `-ports.yaml` (+ports), `-traefik.yaml` (+traefik network)
- FastAPI + Vite + React + Postgres + Redis
- Backend uses Gunicorn + Uvicorn workers, httpx REST clients, no AI SDKs
- Pydantic v2 schemas, asyncpg, redis 8

Files worth studying:

- `docker-compose.yaml` + `-database.yaml` + `-ports.yaml` + `-traefik.yaml` — the deployment-mode pattern
- `CLAUDE.md` — concise project brief
- `backend/config.yaml` + `config.template.yaml` — config template pattern (alternative to `${VAR}` interpolation)
- `scripts/check_and_start_prod.sh` — production start helper

Drifts:

- `data_volume/` at root rather than `data/`
- Compose files at root rather than in `docker/`
- `frontend/`, `backend/` at root rather than under `apps/`

## chimere — Topology 08 (infra orchestrator with Go CLI)

**Location**: `~/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025`

The canonical example for:

- Multi-mode compose tree (`docker/singlenode/`, `docker/multinode/`, `docker/prod/`)
- Go CLI (`cchain/`) orchestrating compose calls with structured state
- Multiple overlay files within `multinode/`: `compose.yaml`, `compose.no-ports.yaml`, `compose.reset.yaml`, `compose.test-temp.yaml`, `compose.traefik.yaml`

Files worth studying:

- `cchain/main.go` + `cchain/cmd/` — cobra-based subcommand structure
- `docker/multinode/compose.yaml` — base for multi-node mode
- `docker/multinode/compose.no-ports.yaml` — overlay example
- `Readme.md` — documents both `./cch` and raw `docker compose` invocations

## plane — Topology 04 (multi-frontend workspaces)

**Location**: `~/projects/03_Self_Hosted_Apps/plane`

The canonical example for:

- True multi-frontend monorepo (6 apps + 15 packages)
- pnpm workspaces + turborepo
- `globalEnv` in `turbo.json` listing every cache-busting var
- Shared `packages/ui`, `packages/tailwind-config`, `packages/typescript-config`, `packages/services`, `packages/types`, etc.
- Caddy-as-proxy in `apps/proxy/`
- Different setup scripts for dev vs prod (`setup.dev.sh` + `setup.prod.sh`) — **we prefer fold-into-`ctl`**, but plane's split is valid for its scale

Files worth studying:

- `pnpm-workspace.yaml` — workspace declaration + version catalog
- `turbo.json` — globalEnv pattern
- `apps/web/`, `apps/admin/`, `apps/space/`, `apps/live/` — per-app structure
- `packages/ui/`, `packages/tailwind-config/` — shared package shape
- `setup.dev.sh` — initial setup orchestration (which our convention folds into `ctl`)

## uvenv — Topology 01 (single-app)

**Location**: `~/projects/02_OpenSource/02_dev_tools/uvenv`
**GitHub**: `https://github.com/sidhanthapoddar/uvenv`

A small CLI tool. Demonstrates:

- Single-app structure (currently with `src/` at root — pre-dates the "no src at root" rule; would migrate to `apps/uvenv/src/`)
- Pure shell, no compose, no frontend
- `install.sh`, `USER_GUIDE.md`, `DESIGN.md`, `CHANGELOG.md` — solid docs hygiene
- VHS tape files in `demo/` for README GIFs

Used as a build dep by ML projects in Topology 07.

## (none yet) — Topology 09 (embeddable package + reference host)

No repo in Sid's current portfolio is a canonical Topology 09 — a published package (UI component / SDK / headless engine) whose real consumer is an *external* host, with a thin in-repo reference host for dev.

When one lands (e.g. an embeddable editor that mounts inside other apps), it becomes the canonical example for:

- The published `packages/<pkg>` as the product; `apps/web` as a reference host (not the deliverable)
- React as a `peerDependency`; per-instance mount model
- Embedding seams (host-injected services / storage / theme)
- Single-artifact delivery (`noExternal` bundling of an internal react-less `core`)
- `package.json` `exports` + library build tooling (tsup/rollup) + versioned publishing

Until then, the skill proposes the pattern on its own merits and flags the absence (see `references/topologies/09_embeddable-package-and-reference-host.md`).

## How the skill cites these

When `/ps-setup` runs:

- Identifies the closest topology
- Points the user at the **most relevant** example for that topology
- For each convention area, can cite a specific file from a specific example

The skill should **never invent paths** from training data. If it can't find a real example for a convention, it should:

1. Cite the convention from this references library
2. Acknowledge "no real-world example exists in Sid's repos for this pattern yet"
3. Propose the convention on its own merits

## Maintenance

This file lists what exists today. As Sid's project portfolio evolves:

- Add new exemplars when they fit a topology cleanly
- Mark old ones as "predates convention X" rather than removing
- Don't migrate the examples to fit the conventions — let them evolve organically, and the references catch up
