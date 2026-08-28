# Stack — the tools, languages and engines we use

A short list on purpose. Pick from it. Add to it only when nothing on it fits, and record the addition in `AGENTS.md`.

## Dev tools

| Tool | Role | Notes |
|---|---|---|
| mise | Version contract for every toolchain | `.mise.toml` at root. `mise install` sets up a clone. Puts the repo root on `PATH`, so `ctl` runs bare. |
| ctl | The single entrypoint for every task | Shell dispatcher into `scripts/`. Owns dev, docker, migrations, tests, builds. See `05_ctl.md`. |
| docker + compose | Runs the data services in dev and the whole stack in prod | Driven only through `ctl`. Compose files in `docker/`. |
| uv | Python packages and venv per backend | `pyproject.toml` + `uv.lock` inside each app. `uv sync`, `uv run`. |
| uvenv | Named global Python envs for ML and notebooks | Our own toolkit over mise + uv. Use it where a `pyproject.toml` per app does not fit. See the `uvenv` skill. |
| bun | JS runtime, package manager, script runner | Preferred. `npm` is the fallback when a tool does not work under bun. |
| AI harness | Claude Code, Codex | Read `AGENTS.md` and `memory/`. Both hosts get the same brief. |
| agent-ks | Docs site and issue tracker | Owns `docs/`. Scaffold with `/agent-ks-init`. |
| lefthook | Git hooks | Format and lint on commit, tests on push. Optional. |

```toml
# .mise.toml
[tools]
bun = "latest"
python = "<version>"
rust = "stable"
uv = "latest"

[env]
_.path = ["{{ config_root }}"]   # ctl runs bare
```

Versions are `<version>` placeholders in every snippet. Resolve each from current stable with the user. Never fill one in from memory.

## Frontend

| Choice | Use when |
|---|---|
| TypeScript, `.tsx` | Always. Plain JS only where a framework forces it. |
| Vite | Default. Every static build, every SPA. |
| Next.js | The frontend needs server-side rendering, or a JS backend is the right backend for the product. |
| Astro | Content sites. Rare. |
| Tailwind | Always, with the standard scale. Design tokens and the styling rules are in `06_frontend.md`. |
| Tauri | Desktop. Rust shell, reuses the web frontend. |
| Electron | Desktop, only when a Node runtime in the shell is required. |
| Kotlin, Swift | Mobile. Native per platform. Share at the API contract, not code. |

## Backend

| Choice | Use when |
|---|---|
| Python, latest stable | Default. FastAPI for HTTP APIs. Flask where a tiny service wants it. |
| Rust | Data plane, throughput, or a Tauri shell. Axum. |
| Go | CLIs, orchestrators, small network services. |
| TypeScript on Node or bun | The needed library exists only in JS, or the product already runs on Next.js. |

One backend per responsibility. A second backend needs a reason: a separate identity plane, a different runtime, or an independent release cadence. See `07_backend.md`.

## Data

| Engine | Role |
|---|---|
| Postgres | Primary relational store. Default for every app with persistent data. |
| Redis | Cache, sessions, queues, streams. |
| SQLite | Single-process apps, local tools, tests. The right floor when Postgres is too much. |
| SeaweedFS | Object store, S3 API. Files and blobs. |
| CouchDB | Document store with sync to clients. |
| LevelDB | Embedded key-value inside one process. |
| Neo4j | Graph queries. Or a faster embedded alternative when the graph is local. |
| Vector DB | Embeddings and similarity search. Start with `pgvector` in Postgres. Move to a dedicated engine only when it outgrows it. |

Pick the engine from the requirement, not from habit. Postgres is the default. Any other engine on the list is a valid choice when the requirement asks for it. Runtime state for all of these lives in `data/`, bind-mounted, gitignored.

## Migrations

Schema changes always go through migrations. Never edit a live schema by hand. There are two ways to own them.

| Way | Where | Use when |
|---|---|---|
| Alembic autogenerate | Inside the backend, next to its models | One backend owns the database, and the schema needs nothing Alembic cannot express. Autogenerate from the models, review the diff, commit the revision. |
| Hand-written migrations | `apps/database/` | Two or more backends read the same database, or the schema uses features autogenerate handles badly: partial or expression indexes, extensions, triggers, custom types, data backfills. Alembic with hand-written revisions, or raw SQL. |

Both conditions must hold for autogenerate: single consumer, plain schema. If either fails, `apps/database/` owns the migrations. One owner in every case.

- `ctl migrate` runs them. `ctl migrate new "<message>"` creates one. Never run `alembic` by hand outside `ctl`.
- Migrations run as an explicit step, not on app boot. In prod, `ctl up prod` runs them once before starting the services.

Recipes and helpers: `assets/python/` (alembic shim and helpers). Details: `07_backend.md`.
