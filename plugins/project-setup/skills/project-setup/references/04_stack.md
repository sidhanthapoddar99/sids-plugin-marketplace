# Stack — what we build with, and when

A short list on purpose. Pick from it. Add to it only when nothing on it fits, and record the addition in `AGENTS.md`. Versions are `<version>` placeholders everywhere; resolve each from current stable with the user, never from memory.

## Dev tools

| Tool | Role | Notes |
|---|---|---|
| mise | Version contract for every toolchain | `.mise.toml` at root. `mise install` sets up a clone. Puts the repo root on `PATH`, so `ctl` runs bare. |
| ctl | The single entrypoint for every task | Shell router into `scripts/`. See `05_ctl.md`. |
| docker + compose | Engines in dev, the whole stack in prod | Driven only through `ctl`. Compose files in `docker/`. |
| uv | Python packages and venv per backend | `pyproject.toml` + `uv.lock` inside each app. |
| uvenv | Named global Python envs for ML and notebooks | Our toolkit over mise + uv. Where a `pyproject.toml` per app does not fit. See the `uvenv` skill. |
| bun | JS runtime, package manager, script runner | Preferred. `npm` is the fallback when a tool does not work under bun. |
| AI harness | Claude Code, Codex | Read `AGENTS.md` and `memory/`. Both hosts get the same brief. |
| agent-ks | Docs site and issue tracker | Owns `docs/`. |
| lefthook | Git hooks | Format and lint on commit, tests on push. Optional. |

Template: `template/.mise.toml`, `template/lefthook.yml`.

## Frontend

### Kinds

| Kind | Output | Served by | Framework | Use when | Template |
|---|---|---|---|---|---|
| SPA | static files | nginx | Vite | The normal app. Logged-in product UI. Default. | `apps/multi-web-app/app/` |
| SSG | static files | nginx | Next.js `output: "export"` | Landing and marketing pages. Strong SEO, no server. | `apps/multi-web-app/landing/` |
| SSR | a Node server | its own container | Next.js `output: "standalone"` | Server rendering, a frontend with its own routes, fast first paint. | `apps/dashboard/` |
| Content | static files | nginx | Astro | Docs, blogs. Rare. | `apps/multi-web-app/docs/` |
| PWA | not a kind | — | — | A manifest and a service worker in the SPA's `public/`. Not an app. | — |

Pick by output. Static kinds live in the group folder and build into one image. A server kind is its own app. How they are wired: `03_setup.md`.

### Language and style

| Choice | Rule |
|---|---|
| TypeScript, `.tsx` | Always. Plain JS only where a framework forces it. |
| Tailwind | Always. Default spacing, type and radius scales. No arbitrary values (`p-[13px]`). |
| shadcn | The component vocabulary. Components live in `apps/packages/ui/`. |
| Theme | One package, `apps/packages/styles/`: `tokens.css` (raw values, light on `:root`, dark on `[data-theme="dark"]`), `globals.css` (Tailwind entry, `@theme inline` maps tokens onto utilities), `elements.css` (base resets). Only colours are ours. One import per app: `@scope/styles/globals.css`. |
| Shared code | `apps/packages/{ui,styles,types,tsconfig}`. Consumed by `link:`. Framework libraries are `peerDependencies`, so the consumer's copy is the only copy. No workspace. |
| Types | `@scope/types` is generated from the API's OpenAPI. Never hand-edited. |

Template: `template/apps/packages/styles/README.md`, `template/apps/packages/ui/package.json`.

## Backend

| Choice | Use when | Framework | Template |
|---|---|---|---|
| Python, latest stable | Default. HTTP APIs, identity, business logic. | FastAPI. Flask where a tiny service wants it. | `apps/api/` |
| Rust | Data plane, throughput, streaming, or a Tauri shell. | Axum | `apps/engine/` |
| Go | CLIs, TUIs, orchestrators, small network services. Ships as one binary. | cobra + Bubble Tea | `apps/cli/` |
| TypeScript on Node or bun | The needed library exists only in JS, or the product already runs a Next.js server. | Next.js route handlers, or Hono | — |

Code layout: Python in `app/` (no `src/`): `main.py`, `config.py`, `routers/`, `services/`, `models/`, `schemas/`, `db/`. Rust in `src/`: `main.rs`, `config.rs`, `routes/`, `db/`. Go: `cmd/<name>/main.go`, `internal/{config,client,ui}/`.

Every backend has: one config loader (`02_env.md`), `/health` (process alive) and `/ready` (dependencies reachable), rate limiting at the router, `X-Forwarded-*` trusted from the edge only, no CORS middleware. AI provider keys live only here, behind a proxy route the frontend calls. An MCP server is a backend app like any other.

One backend per responsibility. Several backends: `03_setup.md` case 5.

## ML and notebooks

| Piece | Rule |
|---|---|
| Training code | `apps/<name>/`, same tree as a backend. Per-experiment settings in `apps/<name>/configs/<experiment>.yaml`, not `config.yaml`. |
| Notebooks | `apps/notebooks/`. Exploration only, never imported by an app. Code an app needs moves into a package. |
| Data, checkpoints, outputs | `data/`. Gitignored by `data/.gitignore`. |
| Environment | `uvenv` named env, or `uv` per app when a `pyproject.toml` fits. |
| Docker | Usually none. `ctl` keeps `dev`, `test`, `lint`; drop `up`. |

Orchestration of remote training, spot instances and inference scaling is out of scope for this skill.

## Desktop and mobile

| Surface | Choice | Shape |
|---|---|---|
| Desktop | Tauri | `apps/desktop/`: the Rust shell loads the built SPA. Electron only when a Node runtime in the shell is required. |
| Terminal | Go + Bubble Tea | `apps/cli/`. `ctl build cli` produces the binary. Not a container. |
| Mobile | Kotlin, Swift | `apps/mobile-android/`, `apps/mobile-ios/`. Native. They share the API contract (`@scope/types`, OpenAPI), never UI code. |

## Data

| Engine | Role |
|---|---|
| Postgres | Primary relational store. Default for every app with persistent data. `pgvector` for embeddings. |
| Redis | Cache, sessions, queues, streams. |
| SQLite | Single-process apps, local tools, tests. The floor when Postgres is too much. |
| SeaweedFS | Object store, S3 API. Files and blobs. |
| CouchDB | Document store with sync to clients. |
| LevelDB | Embedded key-value inside one process. |
| Neo4j | Graph queries. Or a faster embedded alternative when the graph is local. |
| Vector DB | Start with `pgvector`. A dedicated engine only when it outgrows Postgres. |

Pick from the requirement, not from habit. Postgres is the default; any engine on the list is valid when the requirement asks for it. Runtime state lives in `data/`, bind-mounted, gitignored. Committed config lives in `apps/database/<engine>/`. Template: `template/docker/compose.db.yaml`.

## Migrations

Schema changes always go through migrations. Never edit a live schema by hand. Two ways to own them:

| Way | Where | Use when |
|---|---|---|
| Alembic autogenerate | Inside the backend, next to its models | One backend owns the database, and the schema needs nothing autogenerate cannot express. Autogenerate, review the diff, commit. |
| Hand-written | `apps/database/postgres/` | Two or more backends read the same database, or the schema uses what autogenerate handles badly: partial or expression indexes, extensions, triggers, custom types, data backfills. Alembic revisions as a `.py` shim over `.up.sql` / `.down.sql`. |

Both conditions must hold for autogenerate: single consumer, plain schema. If either fails, `apps/database/` owns the migrations. One owner in every case.

- `ctl migrate` applies them. `ctl migrate new "<msg>"` creates one. Never run `alembic` by hand.
- Migrations run as an explicit step, not on app boot. `ctl up` runs them once before the apps start.
- Other engines follow the same verbs: Neo4j constraints in `apps/database/neo4j/init.cypher`, idempotent; Redis config in `apps/database/redis/redis.conf`.

Template: `template/apps/database/README.md`, `template/apps/database/postgres/migrations/versions/0002_indexes.py`.
