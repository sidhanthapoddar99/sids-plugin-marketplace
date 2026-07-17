# Stack decision — which stack does this app use

Owns one decision per app: **which language, framework, runtime, and data engine it uses.** A decision file, zero mechanics — for each app kind it lists the recommended options and the criteria to choose. Every option that has an owner file gets one line + the link; this file never restates a skeleton or a recipe. The default is a **firm** choice you deviate from with a recorded reason (`references/00_altitude-model.md` § evolution machinery) — novelty is not a reason.

## Backend language

| Option | Pick when | Owner |
|---|---|---|
| **Python (uv)** — default | product/API surface, ML-adjacent work, fast iteration | `references/3-app/02-backend/00_app-skeleton.md` |
| **Go** | small static binaries, infra CLIs, the orchestrator itself | `references/2-repo/01-layouts/05_infra-orchestrator.md` |
| **Rust** | perf-critical / systems / correctness-critical services | `references/3-app/02-backend/00_app-skeleton.md` (src-layout note) |
| **Bun (TypeScript)** | TS end-to-end, a BFF that stays close to the frontend | `references/3-app/02-backend/00_app-skeleton.md` |

Default is Python with `uv` for a product backend. Go when the artifact is a small static binary or infra tooling. Rust when a hot path or systems boundary justifies it. Bun when the team is TS-only and the backend is BFF-shaped.

## Web frontend framework

| Option | Pick when | Owner |
|---|---|---|
| **Vite + React** — default | interactive SPA, app behind auth | `references/3-app/03-web-app/00_app-skeleton.md` |
| **Astro** | content-heavy / mostly-static (marketing, docs shell) | `references/3-app/03-web-app/01_framework-variants.md` |
| **Next.js** | SSR / SEO-critical / server-rendered data needs | `references/3-app/03-web-app/01_framework-variants.md` |

## Mobile

Native-first: **Kotlin** (Android) + **Swift** (iOS), two codebases sharing the backend contract — owner `references/3-app/07-mobile-app/00_mobile-app.md`. If the product only needs "installable + mostly-offline web", a **PWA** is the cheaper surface (`references/3-app/03-web-app/02_pwa.md`) — decide native vs PWA before writing either.

## Desktop

**Tauri** by default (small, Rust shell, web-tech UI); **Electron** only when its ecosystem or guaranteed-Chromium behaviour is required — owner `references/3-app/06-desktop-app/00_desktop-app.md`. A desktop shell reuses web `packages/` (ui, tokens, api clients) rather than duplicating them.

## JS runtime + package manager

- **Bun** is the default runtime and installer where the repo is JS-only (single frontend, or JS end-to-end).
- **pnpm workspaces** (with turborepo) when multiple JS apps share `packages/` — the workspace config bodies and the runtime interplay are owned by `references/3-app/01-structure-and-stack/02_workspaces-mechanics.md`; where the workspace roots and packages scope is `references/2-repo/01-layouts/00_grouping-topology.md`.

## Data engine

One line each; the engine-floor decision (and the full selection table) is owned by `references/3-app/04-database/00_provisioning.md` — route there, don't re-decide here.

- **SQLite** — single-service, small, low-write → the floor.
- **Postgres** — concurrent writers / shared / extensions.
- **Redis** — cross-process cache, sessions, streams, TTL.
- **Neo4j** (or embedded Kuzu) — graph queries dominate.

## When the stack is not dictated — ask

- What does this app *do* (product API / infra tool / hot path / content site / installable client)? That picks the language/framework more than preference does.
- Is the repo already single-language? Matching it beats introducing a second runtime.
- Any hard constraint — an existing team skill, a required SDK, a platform (iOS/Android/desktop OS) — that removes the choice?
- Does it need SSR/SEO (→ Next), heavy static content (→ Astro), or is it an app behind auth (→ Vite+React)?

Record the pick and its reason in the project CLAUDE.md structure block, so the next agent inherits the decision instead of re-litigating it.

## Anti-patterns

- **Novelty-driven picks** — choosing a framework because it is new, not because the app needs it.
- **Mixed runtimes without a recorded reason** — a second backend language or JS runtime added silently is drift; if justified, record why.
- **A one-off framework for a single app** in an otherwise uniform repo — raises the maintenance floor for everyone.
- **Reaching for Postgres/Redis reflexively** when SQLite/in-process is the correct floor (`references/3-app/04-database/00_provisioning.md`).
- **Electron by default** when Tauri fits, or **native mobile** when a PWA would satisfy the need.

## See also

- `references/3-app/01-structure-and-stack/00_app-anatomy.md` — the every-app contract this stack plugs into
- `references/3-app/02-backend/00_app-skeleton.md` · `references/3-app/03-web-app/00_app-skeleton.md` — the skeletons per stack
- `references/3-app/04-database/00_provisioning.md` — the engine-floor decision (owner)
- `references/2-repo/01-layouts/00_grouping-topology.md` — workspace rooting + package scope
- `references/00_altitude-model.md` — recording variant choices
