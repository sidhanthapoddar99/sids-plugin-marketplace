# App anatomy — the every-app contract

The rules that hold for **any** app under `apps/` (or a lone top-level `./<name>/`) *before* its kind-specific folder applies — backend, web, desktop, mobile, MCP server, all of them. This file OWNS the cross-kind contract: self-containment, the no-cross-app-imports rule, the app-vs-package test, and what an app folder must and must never hold. The kind skeletons (`02-backend/`, `03-web-app/`, …) build on this and never restate it.

## An app is self-contained

Every app is a unit that runs or deploys on its own. It owns, at its root:

- its **dependency manifest** (`pyproject.toml` / `package.json` / `Cargo.toml` / `build.gradle.kts`),
- its **`config.yaml`** (backends) or env scope (frontends — `VITE_*` / `NEXT_PUBLIC_*`),
- its **own `README.md`** — the host dev loop for this app (strong default #7, `references/2-repo/02-root-hygiene/01_readme-three-paths.md`),
- its **own tests**, co-located per L4 (`references/4-feature/05_caps-and-extraction.md`),
- its **Dockerfile** if it ships as an image (`references/3-app/10-deployment/01_app-packaging.md`),
- **one clear entry point** per its kind's convention (`app.main:app`, `src/main.tsx`, `main.rs`, …).

No app reads another app's config, imports another app's source, or shares a manifest. No symlinks between apps. If two apps need the same value, it comes from the root `.env` via each app's own config surface (`references/2-repo/03-env-config/01_per-service-config.md`), never by reaching sideways.

## No cross-app imports — share only via `packages/`

An app never imports from a sibling app's folder. Code used by two apps moves **down** to the lowest level that contains both consumers — a workspace `packages/<pkg>/` (JS) or a shared library package — whose internals are owned by `references/3-app/05-package/00_shared-packages.md` and whose placement scope is owned by `references/2-repo/01-layouts/00_grouping-topology.md`. A backend and a mobile client share at the **API-contract** level, not the code level; a web app and a desktop shell share `packages/ui` + `packages/styles`, not each other's `src/`.

A direct `import "../../other-app/..."` is a red finding: it welds two deploy units together and defeats the whole point of the app boundary.

## The app-vs-package test

Every new unit answers one question — **is it run/deployed, or imported/published?**

| | **App** (`apps/<name>/` or `./<name>/`) | **Package** (`packages/<name>/`) |
|---|---|---|
| You do this with it | run it, deploy it, `ctl up` it | import it, publish it, consume it in-repo |
| Entry point | a process / server / binary / installable | an export surface (`index.ts`, a wheel) |
| Owns React (if UI) | bundles its own | `peerDependency` when published externally |
| Examples | backend, web frontend, desktop shell, a deployed MCP server | `ui`, `styles`, `types`, a published SDK, a published MCP server |

When the deliverable **is** the package (an external host installs and runs it), that is Layout 06 and the repo's own app becomes a reference host — the publishing fork (exports, peerDeps, semver, single-artifact bundling) is owned by `references/2-repo/01-layouts/06_embeddable-package.md`. Apply this test before creating any folder; getting it wrong mis-frames `apps/` vs `packages/` and loses peerDeps/exports.

## What an app folder must and must not contain

| Must contain | Must never contain |
|---|---|
| its manifest, `config.yaml`/env scope, README, tests, entry point | another app's source or a sideways import |
| its kind's hard skeleton (`app/` for a backend, `src/` for a frontend) | loose scripts that belong in the repo `ctl`/`scripts/` |
| its own `Dockerfile` if imaged | runtime state — that lives in gitignored `data/` (`references/3-app/04-database/00_provisioning.md`) |
| feature folders / modules below the skeleton | committed secrets — those are env vars (`references/2-repo/03-env-config/03_secrets-matrix.md`) |

## Where an app's docs, fixtures, and scripts live

- **Docs** — app-specific notes stay in the app's `README.md`; product/architecture docs are a repo-level `docs/` handoff (`references/1-ecosystem/docs-placement.md`), never duplicated per app.
- **Fixtures / test data** — beside the tests that use them, inside the app (`tests/fixtures/`), never in a shared top-level dump.
- **Scripts** — app-internal helpers live in the app; anything that orchestrates the repo (build, run, migrate) belongs to the root `ctl` + `scripts/` (`references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`), not scattered per app.

## Anti-patterns

- A sibling import (`../other-app/...`) instead of extracting to a package — welds deploy units.
- Two apps sharing one manifest or one `config.yaml` — each app owns its own.
- An app with no README — every app documents its own dev loop.
- Runtime state or secrets committed inside an app folder — state → `data/`, secrets → env.
- Treating a to-be-published unit as an app (or a deployed process as a package) — run the app-vs-package test first.
- A shared "misc"/"common" app that other apps import from — that is a package, not an app.

## See also

- `references/3-app/00_index.md` — the L3 index this contract sits under
- `references/3-app/01-structure-and-stack/01_stack-decision.md` — which stack each app uses
- `references/3-app/05-package/00_shared-packages.md` — package internals (the only sharing seam)
- `references/2-repo/01-layouts/00_grouping-topology.md` — where an app's slot sits; package placement scope
- `references/2-repo/01-layouts/06_embeddable-package.md` — the publishing fork when the deliverable is a package
- `references/2-repo/02-root-hygiene/01_readme-three-paths.md` — the per-app README contract
