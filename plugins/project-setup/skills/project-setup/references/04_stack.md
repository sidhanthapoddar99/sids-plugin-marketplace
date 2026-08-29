# Stack — what we build with, and when

A short list on purpose. Pick from it. Add to it only when nothing on it fits, and record the addition in `AGENTS.md`. Versions are `<version>` placeholders everywhere; resolve each from current stable with the user, never from memory: `mise ls-remote <tool> | tail` shows what exists. Pin majors; avoid `latest` (bun is the pragmatic exception).

This page is the choice. How to build the thing chosen: `05_frontend.md`, `06_backend.md`. What must be safe: `07_security.md`.

## Dev tools

| Tool | Role | Notes |
|---|---|---|
| mise | Version contract for every toolchain | `.mise.toml` at root. `mise install` sets up a clone; `mise trust` once per clone. Its `[env]` block puts the repo root on `PATH`, so `ctl` runs bare. A Rust app still commits `rust-toolchain.toml`: cargo respects that, the mise pin is only an install hint. Never a second version manager beside it (`pyenv`, `nvm`, `.tool-versions`). Not the tool for CUDA-pinned stacks; see ML. |
| ctl | The single entrypoint for every task | Shell router into `scripts/`. See `08_ctl.md`. |
| docker + compose | Engines in dev, the whole stack in prod | Driven only through `ctl`. Compose files in `docker/`. |
| uv | Python packages and venv per backend | `pyproject.toml` + `uv.lock` inside each app. Never `uv pip install` inside an app (bypasses the lock); no `requirements.txt` beside `pyproject.toml`; never hand-edit `uv.lock`. |
| uvenv | Named global Python envs for ML and notebooks | Our toolkit over mise + uv. Where a `pyproject.toml` per app does not fit. See the `uvenv` skill. |
| bun | JS runtime, package manager, script runner | Preferred. `npm` is the fallback when a tool does not work under bun. |
| AI harness | Claude Code, Codex | Read `AGENTS.md` and `memory/`. Both hosts get the same brief. `.mcp.json` at the root is committed project config; secrets in it are `${VAR}`, never literals. |
| agent-ks | Docs site and issue tracker | Owns `docs/`. |
| lefthook | Git hooks | Lint on commit, tests on push. `ctl setup` runs `lefthook install`, or the hooks never fire. |

Template: `template/.mise.toml`, `template/lefthook.yml`.

## Frontend

| Kind | Output | Served by | Framework | Use when | Template |
|---|---|---|---|---|---|
| SPA | static files | nginx | Vite | The normal app. Logged-in product UI. Default. | alone: `apps/example-single-web-app-vite/`; in a group: `apps/example-multi-web-app/app/` |
| SSG | static files | nginx | Next.js `output: "export"` | Landing and marketing pages. Strong SEO, no server. | `apps/example-multi-web-app/landing/` |
| SSR | a Node server | its own container | Next.js `output: "standalone"` | Server rendering, a frontend with its own routes, fast first paint. | `apps/example-dashboard-nextjs/` |
| Content | static files | nginx | Astro | Docs, blogs. Rare. | `apps/example-multi-web-app/docs/` |
| PWA | not a kind | — | — | A manifest and a service worker in the SPA's `public/`. Not an app. See `05_frontend.md`. | — |

Pick by output. One static frontend owns its image. Several static frontends live in a group folder and build into one image. A server kind is its own app. How they are wired: `03_routing.md`.

| Choice | Rule |
|---|---|
| TypeScript, `.tsx` | Always. Plain JS only where a framework forces it. |
| Tailwind v4 | Always. Stock spacing, type and radius scales, never remapped. No arbitrary values (`p-[13px]`). |
| shadcn | The component vocabulary, `new-york`, `cssVariables: true`. |
| Client state | zustand. Server state: TanStack Query, owned by the `api/` layer. Never both for one value. |
| Shared code | `apps/packages/{ui,types,tsconfig}`. Consumed by `link:`. Framework libraries are `peerDependencies`, so the consumer's copy is the only copy. No workspace. |
| Version skew | With no workspace, nothing pins React across apps. Every manifest names the same `<version>`; `ctl check` compares them. |
| Types | `@scope/types` is generated from the API's OpenAPI. Never hand-edited. |
| Theme | Both modes by default; light-only is a choice for marketing pages, recorded in `AGENTS.md`. |

## Backend

| Choice | Use when | Framework | Template |
|---|---|---|---|
| Python, latest stable | Default. HTTP APIs, identity, business logic. | FastAPI. Flask where a tiny service wants it. | `apps/example-api-python/` |
| Rust | Data plane, throughput, streaming, or a Tauri shell. | Axum | `apps/example-engine-rust/` |
| Go | CLIs, TUIs, orchestrators, small network services. Ships as one binary. | cobra + Bubble Tea | `apps/example-tui-go/` |
| TypeScript on Node or bun | The needed library exists only in JS, or the product already runs a Next.js server. | Next.js route handlers, or Hono | — |
| C++ | Compute-intensive work with no UI: numeric kernels, codecs, simulation, anything where Rust's ecosystem lacks the library. Exposed to the rest of the stack as a Python extension (pybind11 / nanobind) or a small gRPC/HTTP service; never called from a frontend. | CMake, one target per binary or module | — |
| Other | A language that gives a specific, named benefit for one piece: an existing library, a runtime, a team's expertise, a platform requirement. Record the reason in `AGENTS.md`. It follows the same contract as every backend (`06_backend.md`). | — | — |

One backend per responsibility. Several backends: `03_routing.md` case 5. An MCP server is a backend app like any other; published for others to run, it is a package.

## Data

| Engine | Role |
|---|---|
| Postgres | Primary relational store. Default for every app with persistent data. `pgvector` for embeddings; reach for an extension (`pg_trgm`, `ltree`, TimescaleDB) before a second engine. |
| Redis | Cache, sessions, rate limits, queues, streams. Only when there is more than one process: a single worker's cache is a dict. |
| SQLite | Single-process apps, local tools, tests. The floor when Postgres is too much. Graduate when a second service writes, write concurrency climbs, or an extension is needed. |
| SeaweedFS | Object store, S3 API. Files and blobs. Never blobs in Redis or Postgres. |
| CouchDB | Document store with sync to clients. |
| LevelDB | Embedded key-value inside one process. |
| Neo4j | Graph queries. Or a faster embedded alternative when the graph is local. |
| Vector DB | Start with `pgvector`. A dedicated engine only when it outgrows Postgres. |

Pick from the requirement, not from habit. Runtime state lives in `data/`, bind-mounted, gitignored. Committed config lives in `apps/database/<engine>/`. How to run each engine well, and migrations: `06_backend.md`. Template: `template/docker/compose.db.yaml`.

## ML and notebooks

| Piece | Rule |
|---|---|
| Training code | `apps/<name>/`, same tree as a backend. Per-experiment settings in `apps/<name>/configs/<experiment>.yaml`, not `config.yaml`. |
| Notebooks | `apps/notebooks/`. Exploration only, never imported by an app. Code an app needs moves into a package. |
| Data, checkpoints, outputs | `data/`. Gitignored by `data/.gitignore`. |
| Environment | Exploration: one shared `uvenv` named env with broad ranges, because heavy GPU libraries are shared across experiments and hard-pinning torch causes CUDA mismatches. A root `uvenv-name` file names it; `ctl` activates it and fails loudly if missing. Exact reproducibility or a shipped model server: that piece becomes its own app with `pyproject.toml` + `uv.lock`; `uv pip compile` is the middle ground. |
| Docker | Usually none for training. `ctl` keeps `dev`, `test`, `gate`, adds `train --config`, `eval --run`, `nb`, `data-prep`; drops `up`. |
| UI or API on top | A separate app. Never inside the training folder. |

Remote training, spot instances, checkpoint resume, inference autoscaling and ML CI belong to a sibling skill, `ml-project-setup`, which builds on this tree. Out of scope here.

## Desktop and mobile

| Surface | Choice | Shape |
|---|---|---|
| Desktop | Tauri | `apps/desktop/`: the Rust shell loads the built SPA; it consumes the same `ui`, `types` packages, never a forked copy. Electron only when the shell needs a Node runtime or when webview parity matters more than size (Tauri uses the system webview: WebKit, WebView2, WebKitGTK; Electron bundles Chromium). Never both in one repo. Code signing per platform in CI on tag, or every user sees an unsigned warning forever. |
| Terminal | Go + Bubble Tea | `apps/example-tui-go/`. `ctl build cli` produces the binary. Not a container. |
| Mobile | Kotlin, Swift | `apps/mobile-android/`, `apps/mobile-ios/`. Native by default; cross-platform (Flutter, React Native) is valid for a small team with simple UI and mostly shared logic. They share the API contract (OpenAPI, a generated client via `ctl mobile-api-codegen`, CI fails when it drifts), never UI code. Per-platform build config (`Config.xcconfig`, `gradle.properties`) with flavours for the API base; there is no root env file on a phone. |
