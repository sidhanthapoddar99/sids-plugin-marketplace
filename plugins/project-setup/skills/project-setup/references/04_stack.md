# Stack — what we build with, and when

A short list on purpose. Pick from it. Add to it only when nothing on it fits, and record the addition in `AGENTS.md`. Versions are `<version>` placeholders everywhere; resolve each from current stable with the user, never from memory: `mise ls-remote <tool> | tail` shows what exists. Pin majors; avoid `latest` (bun is the pragmatic exception).

## Dev tools

| Tool | Role | Notes |
|---|---|---|
| mise | Version contract for every toolchain | `.mise.toml` at root. `mise install` sets up a clone; `mise trust` once per clone. Its `[env]` block puts the repo root on `PATH`, so `ctl` runs bare. A Rust app still commits `rust-toolchain.toml`: cargo respects that, the mise pin is only an install hint. Not the tool for CUDA-pinned stacks; see ML. |
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
| SPA | static files | nginx | Vite | The normal app. Logged-in product UI. Default. | alone: `apps/example-single-web-app-vite/`; in a group: `apps/example-multi-web-app/app/` |
| SSG | static files | nginx | Next.js `output: "export"` | Landing and marketing pages. Strong SEO, no server. | `apps/example-multi-web-app/landing/` |
| SSR | a Node server | its own container | Next.js `output: "standalone"` | Server rendering, a frontend with its own routes, fast first paint. | `apps/example-dashboard-nextjs/` |
| Content | static files | nginx | Astro | Docs, blogs. Rare. | `apps/example-multi-web-app/docs/` |
| PWA | not a kind | — | — | A manifest and a service worker in the SPA's `public/`. Not an app. | — |

Pick by output. One static frontend owns its image. Several static frontends live in a group folder and build into one image. A server kind is its own app. How they are wired: `03_setup.md`.

### Language and style

| Choice | Rule |
|---|---|
| TypeScript, `.tsx` | Always. Plain JS only where a framework forces it. |
| Tailwind v4 | Always. Default spacing, type and radius scales. No arbitrary values (`p-[13px]`). |
| shadcn | The component vocabulary, `new-york`, `cssVariables: true`. |
| Shared code | `apps/packages/{ui,types,tsconfig}`. Consumed by `link:`. Framework libraries are `peerDependencies`, so the consumer's copy is the only copy. No workspace. |
| Version skew | With no workspace, nothing pins React across apps. Every manifest names the same `<version>`; `ctl check` compares them. |
| Types | `@scope/types` is generated from the API's OpenAPI. Never hand-edited. |

### Theme

The theme and the components are one thing, with one internal shape wherever it lives:

```
styles/     tokens.css    raw values only. Colours by role (--bg-1..3, --fg-1..3, --border-1..2), light on :root,
                          dark on [data-theme="dark"]. Radius base, fonts, motion. Nothing else switches by theme.
            globals.css   the Tailwind entry. @import tailwindcss + tokens + elements. @theme = the default scales.
                          @theme inline = tokens mapped onto utilities (--color-bg-1: var(--bg-1)) plus the shadcn
                          aliases (--color-background, --color-primary …). @source points at the components.
            elements.css  base element resets that consume tokens.
components/ shadcn components, one file each, a folder for compound ones.
lib/utils.ts  cn()
```

| Product has | Where the shape lives | Import in the app |
|---|---|---|
| one frontend | inside the app: `src/styles/`, `src/components/ui/`, `src/lib/` — the standard shadcn layout | `import "./styles/globals.css"` |
| two or more | `apps/packages/ui/src/`, the same folders, linked by every frontend | `import "@scope/ui/globals.css"` |

Moving from the first to the second is a move, not a rewrite. Rules that hold in both:

- One CSS import per app, in the entry file. Nothing else imports CSS.
- A colour is named once, in `tokens.css`, by role, never by hue. A component uses the utility (`bg-bg-1`, `border-thin`), never `var(--…)`, never a hex.
- Variants differ by fill and border; sizes use the default scale (`px-3 py-1 text-sm rounded-sm`).
- `cn()` is taught the named utilities `globals.css` adds (`border-thin`, `duration-fast`), or tailwind-merge drops them.
- In the package, React and Tailwind are peerDependencies; React optional, so a CSS-only consumer (Astro docs) links it without React.

Template: `template/apps/packages/ui/README.md` (the package), `template/apps/example-single-web-app-vite/src/` (the in-app shape).

### Published package or SDK

When the product is a library, it lives in `apps/packages/<name>/` and the frontend beside it is a dev harness (`01_layout.md`). Rules that differ from an app:

| Rule | Detail |
|---|---|
| Public surface | An `exports` map names every entry; consumers cannot deep-import. `files: ["dist"]`. |
| Build | A library build (`vite build --lib`, tsup), `external: ["react"]`, framework in `devDependencies` + `peerDependencies`. Not app bundling. |
| Internal split | A react-less `core` package for authors, bundled into the one published artifact (`noExternal`) for consumers. |
| Source-only phase | `private: true`, `exports` pointing at `src/`, no `dist/`. Ends at the first external consumer. Record it in `AGENTS.md` as the chosen stage. |
| Embeddable | Reads no env: services, storage and theme arrive as injected config at mount. No module-level singletons; the same package may mount several times on one page. Clean teardown on unmount. |

### PWA

A PWA is the SPA plus a manifest and a service worker, generated by the build, never a hand-written `sw.js`. Choose native instead when the product needs store presence, background execution, device APIs, or reliable iOS push (web push works only for an installed PWA). Choose the offline scope explicitly: none, read-only shell, or full sync; half-offline is worse than online. Never blanket-cache `/api/*`; freshness per route.

## Backend

| Choice | Use when | Framework | Template |
|---|---|---|---|
| Python, latest stable | Default. HTTP APIs, identity, business logic. | FastAPI. Flask where a tiny service wants it. | `apps/example-api-python/` |
| Rust | Data plane, throughput, streaming, or a Tauri shell. | Axum | `apps/example-engine-rust/` |
| Go | CLIs, TUIs, orchestrators, small network services. Ships as one binary. | cobra + Bubble Tea | `apps/example-tui-go/` |
| TypeScript on Node or bun | The needed library exists only in JS, or the product already runs a Next.js server. | Next.js route handlers, or Hono | — |
| C++ | Compute-intensive work with no UI: numeric kernels, codecs, simulation, anything where Rust's ecosystem lacks the library. Exposed to the rest of the stack as a Python extension (pybind11 / nanobind) or a small gRPC/HTTP service; never called from a frontend. | CMake, one target per binary or module | — |
| Other | A language that gives a specific, named benefit for one piece: an existing library, a runtime, a team's expertise, a platform requirement. Record the reason in `AGENTS.md`. It follows the same contract as every backend: one config loader, `/health` and `/ready`, its own prefix in `.env.proxy`, its own image. | — | — |

Code layout grows with the number of domains:

| Size | Shape |
|---|---|
| A few endpoints | Flat `app/`: `main.py`, `config.py`, `db.py`, `routes.py`, `models.py`. |
| Several domains — the normal backend | Domain slices: `app/<domain>/{models,repository,service,router}.py`, plus `app/core/` for cross-cutting (security, redis, rate limit), `app/health/`, and `main.py` to compose. Inside a slice `router → service → repository`; across slices `service → service` only. A domain's public surface is its `service`. |
| Layers reused by more than one binary, or compiled apart (Rust) | A cargo workspace, one crate per layer: `common` (config, errors), `data` (every query), `auth`, and a thin `api` binary with one handler module per domain. `api → auth, data → common`. `rust-toolchain.toml` is the real pin. |
| Go CLI | `cmd/<name>/main.go`, `internal/{config,client,ui}/`. |

Python lives in `app/`, never `src/`. Template: `template/apps/example-api-python/README.md`, `template/apps/example-engine-rust/README.md`.

Every backend has: one config loader (`02_env.md`), `/health` (process alive) and `/ready` (dependencies reachable), rate limiting at the router, `X-Forwarded-*` trusted from the edge only, no CORS middleware. AI provider keys live only here, behind a proxy route the frontend calls. An MCP server is a backend app like any other.

One backend per responsibility. Several backends: `03_setup.md` case 5.

### Security floor

| Concern | Where | Rule |
|---|---|---|
| Edge protection | nginx, or a host proxy in front | TLS, body size limit, proxy timeouts. |
| Captcha | public forms: signup, login, contact, anything unauthenticated that writes | Cloudflare Turnstile, or the best privacy-respecting option at the time; check before choosing. The widget's site key is a build constant in the frontend; the secret key lives in `.env.secrets`; the backend verifies the token on every submit and rejects without it. Never on authenticated routes. |
| Rate limiting | the backend router, keyed by user or IP from `X-Forwarded-For` | Per-route limits in `config.yaml` (`limits.rate_per_minute`). Redis-backed when there is more than one replica. |
| Auth tokens | `core/security.py` | Short-lived signed access tokens, opaque refresh tokens in Redis, argon2 passwords. One `JWT_SIGNING_KEY` shared with every validator. |
| AI and third-party keys | `.env.secrets`, backend only | The frontend calls a proxy route. Per-user quota on that route. |
| Audit and telemetry | a domain slice (`audit/`) | Who did what, structured, to stdout; a table when it must be queried. Never a secret or a body in a log. |

## ML and notebooks

| Piece | Rule |
|---|---|
| Training code | `apps/<name>/`, same tree as a backend. Per-experiment settings in `apps/<name>/configs/<experiment>.yaml`, not `config.yaml`. |
| Notebooks | `apps/notebooks/`. Exploration only, never imported by an app. Code an app needs moves into a package. |
| Data, checkpoints, outputs | `data/`. Gitignored by `data/.gitignore`. |
| Environment | Exploration: one shared `uvenv` named env with broad ranges, because heavy GPU libraries are shared across experiments and hard-pinning torch causes CUDA mismatches. A root `uvenv-name` file names it; `ctl` activates it and fails loudly if missing. Exact reproducibility or a shipped model server: that piece becomes its own app with `pyproject.toml` + `uv.lock`; `uv pip compile` is the middle ground. |
| Docker | Usually none for training. `ctl` keeps `dev`, `test`, `lint`, adds `train --config`, `eval --run`, `nb`, `data-prep`; drops `up`. |
| UI or API on top | A separate app. Never inside the training folder. |

Remote training, spot instances, checkpoint resume, inference autoscaling and ML CI belong to a sibling skill, `ml-project-setup`, which builds on this tree. Out of scope here.

## Desktop and mobile

| Surface | Choice | Shape |
|---|---|---|
| Desktop | Tauri | `apps/desktop/`: the Rust shell loads the built SPA; it consumes the same `ui`, `types` packages, never a forked copy. Electron only when the shell needs a Node runtime or when webview parity matters more than size (Tauri uses the system webview: WebKit, WebView2, WebKitGTK; Electron bundles Chromium). Never both in one repo. Code signing per platform in CI on tag, or every user sees an unsigned warning forever. |
| Terminal | Go + Bubble Tea | `apps/example-tui-go/`. `ctl build cli` produces the binary. Not a container. |
| Mobile | Kotlin, Swift | `apps/mobile-android/`, `apps/mobile-ios/`. Native by default; cross-platform (Flutter, React Native) is valid for a small team with simple UI and mostly shared logic. They share the API contract (OpenAPI, a generated client via `ctl mobile-api-codegen`, CI fails when it drifts), never UI code. Per-platform build config (`Config.xcconfig`, `gradle.properties`) with flavours for the API base; there is no root env file on a phone. |

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
