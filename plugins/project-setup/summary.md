# project-setup — spec

The distilled spec for this plugin. `Notes.md` is the raw braindump; this is the structured form of what's agreed.

## Mission

When Sid (or anyone using his conventions) starts a new project, or works inside an existing one, Claude should follow established conventions for layout, configuration, tooling, and runtime — rather than inventing fresh patterns each time.

But: **there is no single ideal structure**. What's right depends on shape questions (mono vs poly, how many backends, how many frontends, app vs ML, deployment surface). So this plugin is built around three things, in order:

1. A **knowledge base** of recognised topologies and the conventions that apply to each.
2. A **question-asker** that interrogates before recommending. Unknowns → ask, don't presume.
3. A **layout proposer** that, only after the questions are answered, produces concrete output.

The same machinery powers three modes:

- **init** — bootstrap a new repo
- **audit** — scan an existing repo, report drift from conventions
- **suggest** — propose an ideal structure for a half-done repo

## Shape of the plugin

- **One skill** — `project-setup` — owns triage + the references library
- **One slash command** — `/ps-setup` — three modes (`init` default, `audit`, `suggest`)
- **References library** — fat, organised by topic, cited by the skill and command
- **Snippets** — focused fragments the skill points at and the command can drop in. Not a full project template.

## Topology library

| # | Name | When it fits | Canonical example |
|---|---|---|---|
| 01 | single-app | A single CLI / library / service. No frontend, no microservices. | uvenv |
| 02 | monorepo, 1 backend + 1 frontend | The common product case. | NeuraSutra |
| 03 | monorepo, multi-backend microservices | Two or more backends in different languages coordinating via Redis/DB. | atheneum (Python + Rust) |
| 04 | monorepo, multi-frontend workspaces | Multiple frontends sharing a `packages/ui` / `packages/styles`. | plane (turborepo + pnpm, 6 apps + 15 packages) |
| 05 | monorepo, microservices mesh | Many small backends each with their own service boundary. | — |
| 06 | polyrepo with deploy aggregator | Each service in its own repo plus a `-deploy` repo aggregating env + compose. | — |
| 07 | ML project | uvenv-driven global env, `requirements.txt`, no frontend, no compose. | — |
| 08 | infra orchestrator | Docker compose tree driven by a Go CLI. | chimere multinode |

Each topology has a reference file under `skills/project-setup/references/topologies/`.

## Decisions locked in (the answers I had to ask)

| Question | Decision |
|---|---|
| Default compose location | `docker/` folder by default, with multiple deployment-mode files (`compose.yaml`, `compose.database-only.yaml`, `compose.dev.yaml`, `compose.prod.yaml`, `compose.traefik.yaml`, `compose.no-ports.yaml`). Root-only single-file compose allowed for the simplest single-app case. |
| Frontend workspace tool | Bun is the default for solo Vite; for multi-frontend monorepos use whatever fits best (pnpm + turborepo is the polished answer for Vite + React; let circumstances decide for Next/Astro). |
| `.claude/` standard contents | Leave empty initially; build up as patterns emerge. The bootstrapper just creates the folder + a `CLAUDE.md` next to it. |
| Setup vs dev scripts | Fold both into one `./dev` script with subcommands. No separate `setup.dev.sh`. |
| `config.yaml` schema | No mandatory schema. Teach `${VAR}` interpolation and ship illustrative example sections (db / redis / app / auth / search) so the skill has concrete patterns to cite. Examples non-prescriptive. |
| `src/` location | **Never at repo root.** Always nested inside `apps/<name>/src/` (or `packages/<name>/src/`) so there's room to grow without restructuring. |

## Conventions encoded (the skill teaches these)

### Env + config

- **Root `.env`** carries shared / common vars only (DB creds, redis creds, shared ports, JWT/encryption keys, domain). Gitignored. `.env.example` committed as the contract.
- **Per-service `config.yaml`** lives next to each backend's code (`apps/backend/config.yaml`). Reads root `.env` via `${VAR}` interpolation. Non-secret only.
- **Frontend has its own env scope** — `VITE_*` / `NEXT_PUBLIC_*` get baked into the bundle and shipped to the browser. Backend secrets must never appear in the frontend env file. Each frontend's env lives next to it, not at repo root.
- **`config.local.yaml`** (gitignored) takes precedence over `config.yaml` for local-only overrides.
- **Build-time vs runtime** distinction is explicit. Build-time vars (Vite `VITE_*`, Next `NEXT_PUBLIC_*`) bake at build. Runtime vars (server-side) load at boot. The skill flags every variable as one or the other.

### Secrets matrix

| Env | Where | Notes |
|---|---|---|
| Local dev | `.env`, `.env.local`, `config.local.yaml` | Gitignored. Generate via `openssl rand -hex 32` instructions in `.env.example`. |
| CI | GitHub Actions secrets / self-hosted runner env | Reference `.env.example` keys as the contract. |
| Prod | `.env.production` for compose `env_file`; later Vault / 1Password | Same `.env.example` contract; rotation policy lives in `secrets-matrix.md`. |

### Docker compose

- **All compose files in `docker/`** (or `docker/<mode>/` for orchestrator-driven repos).
- **Files represent deployment modes**, not concerns:
  - `compose.yaml` — base (services, no host ports)
  - `compose.database-only.yaml` — only postgres + redis, for the "apps on host" dev mode
  - `compose.dev.yaml` — adds host ports
  - `compose.prod.yaml` — production overrides
  - `compose.traefik.yaml` — adds Traefik external network overlay
  - `compose.no-ports.yaml` — removes host ports
- **Bind-mounts only**, no named volumes. State lives under `data/<service>/` with a `.gitkeep`.
- **Nested data dir trick** for Postgres: bind-mount `data/postgres/pgdata` (the empty nested dir), not `data/postgres/` (which contains `.gitkeep` and breaks initdb).
- **Escalation rule**: when shell wrappers grow beyond ~150 lines or need structured state across compose calls, swap to a small Go CLI (chimere pattern). Most projects never hit this.

### Scripts

- **One global wrapper at repo root**: `./dev`. Single entrypoint. Bare `./dev` runs first-run flow; subcommands handle day-to-day flows (`./dev migrate`, `./dev test`, `./dev clean`, `./dev help`).
- **Subscripts in `scripts/`** are the targets the wrapper calls (`scripts/db-init.sh`, `scripts/check-env.sh`, etc.). The wrapper is the public API; scripts are implementation.
- **Setup folds into `./dev`** — no separate `setup.dev.sh` / `setup.prod.sh`. If first-run flow gets long, split via subcommand (`./dev install`), not a separate script.
- **README documents three startup paths**: (1) `./dev` (preferred), (2) raw `docker compose -f docker/compose.dev.yaml up`, (3) no-docker host run (`cd apps/backend && uv run …`).

### Python

- **Apps**: `pyproject.toml` + `uv.lock` + `uv sync`. `requirements.txt` only as a generated build artefact if Docker images can't have uv.
- **ML**: `requirements.txt` + uvenv global env. Different on purpose — ML libs are global and shared across experiments.
- **Migrations**: Alembic by default. Atheneum's raw-`.sql` + 3-line-Python-shim pattern is documented for projects where Rust consumes the schema. Auto-generation is fine for simple cases; hand-written for complex/multi-tenant.

### Frontend

- **Vite is the default**, with TypeScript + shadcn/ui + Tailwind + Radix. Bun is the package manager unless a framework requires otherwise.
- **Next.js / Astro** are first-class alternatives; let circumstances decide.
- **Vite proxy in dev → nginx in prod**, all backends reachable under `/api/*` from the frontend. CORS-free.
- **Design tokens** in one CSS file (`apps/<frontend>/src/styles/tokens.css` for single-frontend; `packages/styles/tokens.css` for multi-frontend). Components use `var(--token)` references only. No hex, no raw px in component CSS. Three font sizes (13 / 15 / 18 px) as default.
- **Light + dark** via `[data-theme="dark"]` on `:root`. Both modes by default; opt-in to light-only for marketing pages.
- **Multi-frontend** uses pnpm + turborepo (default) or bun workspaces. Shared via `packages/ui`, `packages/tailwind-config`, `packages/typescript-config`, `packages/styles`, `packages/services`, `packages/types`.

### Modularity

- **Hard cap**: 500 lines per file. Split before committing.
- **Soft target**: ≤ 300 lines per file. Past this look for a natural split.
- **Folders by feature**, not by kind. `auth/`, `workspaces/`, `blocks/` — each owns its routes + models + services. Avoid `controllers/`, `models/`, `helpers/` buckets.
- **Extract on third use**, not earlier. Three usages → shared helper. One or two → inline.

### Mise + version pinning

- `.mise.toml` is the runtime version contract. `mise install` from a clean clone must produce a working toolchain. Pin Python, Node/Bun, Rust toolchain (via `rust-toolchain.toml`), Go.

### Docs

- **Monorepo**: in-repo `docs/` via documentation-template plugin. `/ps-setup` hands off to `/docs-init`.
- **Polyrepo**: dedicated docs repo (`<product>-docs`).
- README at every repo root.

### `.claude/` folder

- Created empty by `/ps-setup`. Built up as patterns emerge.
- `CLAUDE.md` next to the folder is the agent-facing brief — what the repo is, hard rules, where to look.

## Project layout — Topology 02 reference (monorepo 1be + 1fe)

```
my-app/
├── .env / .env.example              # shared vars only
├── .env.production                  # optional, compose env_file
├── .mise.toml
├── dev                              # ./dev — single entrypoint
├── docker/
│   ├── compose.yaml                 # base
│   ├── compose.database-only.yaml
│   ├── compose.dev.yaml             # +ports
│   ├── compose.prod.yaml
│   ├── compose.traefik.yaml
│   └── compose.no-ports.yaml
├── scripts/                         # subscripts called by ./dev
│   ├── db-init.sh
│   └── check-env.sh
├── apps/
│   ├── backend/
│   │   ├── pyproject.toml + uv.lock
│   │   ├── config.yaml              # per-service; reads root .env
│   │   ├── config.local.yaml        # gitignored
│   │   ├── alembic/
│   │   ├── src/<package>/           # ← src ALWAYS nested
│   │   ├── tests/
│   │   └── Dockerfile
│   └── frontend/
│       ├── package.json + bun.lockb
│       ├── .env / .env.example      # frontend-scoped (VITE_* only)
│       ├── vite.config.ts           # proxies /api/* in dev
│       ├── src/
│       │   ├── styles/
│       │   │   ├── tokens.css       # ← THE design tokens file
│       │   │   ├── globals.css
│       │   │   └── elements.css
│       │   ├── components/
│       │   ├── lib/
│       │   └── pages/
│       └── Dockerfile
├── infra/                           # CONFIG only
│   ├── nginx/nginx.conf
│   ├── postgres/init/01_extensions.sql
│   └── traefik/dynamic.yaml         # reference, not enabled by default
├── data/                            # bind-mount targets, gitignored except .gitkeep
│   ├── postgres/pgdata/.gitkeep
│   └── redis/data/.gitkeep
├── docs/                            # documentation-template
├── .claude/                         # empty initially
└── README.md / CLAUDE.md
```

Other topologies are in `skills/project-setup/references/topologies/`.

## What this plugin does NOT do

- Does **not** ship a complete project template. Templates rot; the snippets library + skill that knows where to put them ages better.
- Does **not** prescribe a workspace tool when one isn't strictly needed. For single-app / single-frontend cases, no `pnpm-workspace.yaml` / `turbo.json`.
- Does **not** force ML projects into the app shape. Topology 07 has its own conventions.
- Does **not** edit anything without confirming. `/ps-setup audit` is read-only by default; `init` and `suggest` show the plan before applying.
- Does **not** assume — if information is missing (sibling repos, ML vs app, theming requirements, deployment targets), the skill asks.

## Examples cited

- atheneum — `~/projects/02_OpenSource/04_knowledge_management/atheneum` — multi-backend pattern
- NeuraSutra — `~/projects/06_04_NeuraSutra/neurasutra-api-management` — single backend + frontend
- chimere — `~/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025` — infra orchestrator
- plane — `~/projects/03_Self_Hosted_Apps/plane` — multi-frontend workspaces

Examples are not perfect — they evolved at different times with different constraints. Cited as evidence, not gospel.
