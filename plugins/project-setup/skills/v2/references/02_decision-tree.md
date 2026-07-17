# Decision tree

Maps the question-flow answers (`references/01_question-flow.md`) onto a layout and the major cross-cutting decisions. Consult this AFTER the questions are answered, not before.

**Altitude note:** this file is the **L2 layout picker** inside the four-level altitude model (`references/00_altitude-model.md` — classify a decision's level first; the charters route everything that isn't layout selection). Step 1 below is the L1 deployed-vs-distributed question; everything after it is L2, plus routing pointers into L3 owners (tokens, platform targets, `app/` vs `src/`).

## Layout selection

The **first cut** is *deployed vs distributed* — does the repo run the product, or publish a package an external host runs? (Criteria + tell-tales owned by `references/1-ecosystem/repo-boundaries.md`.) Most repos are deployed (Layouts 01–05). If the deliverable is a package a separate host consumes, it's Layout 06 regardless of how many backends/frontends it has internally.

```
STEP 1 — does this repo RUN the product, or PUBLISH a package an external host runs?
├── Distributed — deliverable is a published package; the repo's own app (if any) is just a reference host
│   └── → Layout 06 (embeddable package + reference host)   [skip Step 2]
└── Deployed — the repo runs the product → continue to Step 2

STEP 2 — (deployed only) pick the deployed layout:
├── Multiple repos working together         → Layout 03 (polyrepo with deploy aggregator)
└── Single repo
    ├── ML project (training, experiments, notebooks)?         → Layout 04 (ML project)
    ├── Multi-node / complex compose graph driven by a Go CLI? → Layout 05 (infra orchestrator) — usually wraps one of the below
    ├── Exactly ONE runnable app (a single backend, CLI, lib, or lone frontend)? → Layout 01 (single app / service)
    └── TWO OR MORE apps in the repo (any mix of backends + frontends)           → Layout 02 (multi-app monorepo)
```

**The number of backends/frontends is a parameter of Layout 02, not a separate layout.** Inside the multi-app monorepo:

- multiple backends → coordinate via Postgres / Redis Streams / HTTP (see the layout's *more-than-one-backend* section); if the second backend exists for a separate **identity/security plane** (operator vs end-user), apply `references/3-app/02-backend/02_two-plane-split.md` (incl. the neutral `apps/db` migrations owner)
- multiple frontends sharing UI/types/styles → `packages/` workspaces (pnpm + turborepo)
- **how `apps/` is arranged is its own decision** — flat / plane-grouped / hybrid, plus where the workspace roots and packages scope: owned by `references/2-repo/01-layouts/00_grouping-topology.md`
- many small services each with their own boundary/deploy cadence → the mesh end of the spectrum (the signal you may be approaching Layout 03 or 05)

See `references/2-repo/01-layouts/02_multi-app-monorepo.md`.

## Per-layout defaults

| Layout | Workspace tool | Compose layout | `ctl` shape |
|---|---|---|---|
| 01 single app / service | none | optional `docker/` | bare entrypoint, few subcommands |
| 02 multi-app monorepo | none; pnpm + turborepo when multiple frontends share code | `docker/` base (whole stack) + standalone configs + `.m.` modifiers; `docker/<svc>/` per service at the mesh end | full subcommand set; language-aware (migrate, sqlx-prepare, test, …); dispatches to per-app builds |
| 03 polyrepo + aggregator | n/a | only the aggregator repo has compose (image-based, no build) | aggregator owns `ctl up prod`; each service repo has its own `ctl` |
| 04 ML | uvenv | none typically | `ctl train`, `ctl eval`, `ctl serve` |
| 05 infra orchestrator | go (the orchestrator binary itself) | `docker/<mode>/` tree | go binary at root |
| 06 embeddable package + reference host | pnpm/bun workspace (package + reference `apps/web`) | optional — only for the reference host's deps | `ctl dev` runs the reference host; `ctl build` builds the package; `ctl publish` ships it |

## Per-layout cross-cutting decisions

### Where does code live? (`app/` vs `src/`)

An L3 (app-level) decision — **owned elsewhere, don't restate here**. The one L2 fact this picker needs: **one app total → top-level `./<name>/`; two or more → group under `apps/<name>/`** (this is the physical difference between Layout 01 and 02). The inner-layout rule (flat `app/` for run-services, `src/` for frontends and packages, nothing loose in root) and the per-layout path patterns live in `references/3-app/02-backend/00_app-skeleton.md` (backends) and `references/3-app/03-web-app/00_app-skeleton.md` (frontends).

### `apps/` vs `packages/` — three categories, not two

The common framing is "`apps/` = deployables, `packages/` = internal shared code." That's incomplete: it has no slot for a repo whose *deliverable is a package an external host runs*. Split into **three**:

| Category | Lives in | Built/shipped as | React (if UI) | Versioned + published? |
|---|---|---|---|---|
| **Deployable app** | `apps/<name>/` | a running process / image you deploy | bundled (owns its React) | no |
| **Internal shared lib** | `packages/<name>/` | consumed *in-repo* by sibling apps via the workspace | bundled by the consuming app | no (workspace-internal) |
| **Published product package** | `packages/<name>/` (the product) | an artifact installed by an **external** repo (npm / PyPI) | **`peerDependency`** — the host owns the React instance | **yes** — `package.json` `exports`, build tooling (tsup/rollup), semver |

The third category is the one the two-category model erases. When the deliverable is the package itself (Layout 06), the repo's `apps/web` is a **reference host** — a dev harness — not the product. Publishing mechanics (exports, peerDeps, single-artifact bundling) live in `references/2-repo/01-layouts/06_embeddable-package.md`; the embedding-seams (inversion-of-control) pattern in `references/3-app/05-package/02_embeddable-seams.md`.

### Where does `config.yaml` live?

| Layout | Path |
|---|---|
| 01 | `./<name>/config.yaml` (single service, top-level) |
| 02 | `apps/<service>/config.yaml` per backend (frontend optional) |
| 03 | inside each repo, next to its service |
| 04 (ML) | `configs/<experiment>.yaml` (per-experiment) |
| 05 | per-service inside `apps/`; orchestrator config in its own folder |
| 06 | n/a — no deployed service; an optional reference-host BFF follows Layout 02's rule |

**Never `config.yaml` at repo root.** Root has only `.env` / `.env.example`. Full rule: `references/2-repo/03-env-config/01_per-service-config.md`.

### Where do env vars live?

| Variable type | Location |
|---|---|
| Backend secrets, DB creds, shared infra ports | Root `.env` |
| Frontend-public build vars (`VITE_*`, `NEXT_PUBLIC_*`) | `apps/<frontend>/.env` (per frontend) |
| Per-experiment hyperparameters (ML) | `configs/<experiment>.yaml` |
| Production overrides | `.env.production` (compose `env_file`) |
| Local overrides | `.env.local`, `config.local.yaml` (gitignored) |

See `references/2-repo/03-env-config/00_env-precedence.md` for the load order (root → per-service → real env wins).

### What compose structure does the layout need?

Two axes (profile-less) — at most one standalone **`config`** (a `compose.<name>.yaml` that *replaces* base; `data`, `prod`) and stackable **`.m.` modifiers** (`--modifier expose,traefik`). The filenames, the `ctl up` grammar, the per-layout footprint, and worked examples are the canonical doc's job — **owned by `references/2-repo/04-docker/00_docker-overview.md`** (orchestrator trees: `references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md`). Don't restate them here.

### Python flow per layout

| Layout | Python flow |
|---|---|
| 01 | `pyproject.toml` + `uv.lock` + `uv sync` |
| 02 | `pyproject.toml` + `uv.lock` per Python backend |
| 03 | per-repo, modern flow |
| 04 (ML) | `requirements.txt` + uvenv global env (different on purpose) |
| 05 | `pyproject.toml` + `uv.lock` per Python service |
| 06 | n/a — JS package repo; an optional reference-host BFF follows Layout 02's rule |

### Frontend tooling per layout

| Layout | Frontend tool |
|---|---|
| 01 | n/a (or Vite + bun if it's a lone frontend) |
| 02 | Vite + bun (single frontend); Vite + pnpm + turborepo + shared `packages/ui` (multiple frontends) |
| 03 | per-repo |
| 04 | none typically |
| 05 | rarely; if present, same as 02 |
| 06 | the published UI package + a Vite reference host |

### Design tokens location

Single frontend → `apps/frontend/src/styles/tokens.css`; multiple frontends → shared `packages/styles/src/tokens.css` — owned by `references/3-app/05-package/01_tokens-setup.md`.

### Platform targets (non-web surfaces)

Web is the default surface. A repo may also target — ask before assuming web-only (question-flow Q16):

| Surface | What it is | Owner |
|---|---|---|
| **Mobile** | native iOS (Swift) + Android (Kotlin), own codebases under `apps/`, sharing the backend contract | `references/3-app/07-mobile-app/00_mobile-app.md` |
| **Desktop** | Tauri (default) / Electron wrapper; shares `packages/` with web | `references/3-app/06-desktop-app/00_desktop-app.md` |
| **PWA** | the *existing* web frontend made installable + offline (manifest + service worker) — **not** a new app under `apps/` | `references/3-app/03-web-app/02_pwa.md` |

PWA and native are not exclusive — a product can ship both over one backend contract.

### Docs location

In-repo `docs/` for single-repo layouts (01, 02, 04, 05); a separate `<product>-docs` repo for Layout 03 — decision + `agent-ks` handoff owned by `references/1-ecosystem/docs-placement.md`.

## Escalation rules

These decisions only apply once a project crosses a complexity threshold. The layout-internal (L2) migrations are owned here; the boundary escalations (mono→poly, deployed→distributed, aggregator) are owned by `references/1-ecosystem/repo-boundaries.md` — one line each below.

| Trigger | Action |
|---|---|
| `ctl` shell dispatcher crosses tripwire T7 (size / structured state across compose runs) | Move orchestration to a Go binary (Layout 05; threshold + criteria: `references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md`). |
| A single app grows a second app (backend or frontend) | Migrate Layout 01 → 02: introduce `apps/`, move the existing app under `apps/<name>/`. |
| Within Layout 02, frontends start sharing code | Introduce `pnpm-workspace.yaml` + `turbo.json` + `packages/` — still Layout 02. |
| Within Layout 02, services grow independent deploy cadences/boundaries | The mesh end of Layout 02; separate repos → Layout 03 (`references/1-ecosystem/repo-boundaries.md`). |
| `requirements.txt` flow grows reproducibility needs | Migrate Layout 04-style → 01-style with `pyproject.toml` + `uv.lock`. |
| Two repos start sharing env vars | Introduce a Layout 03 aggregator repo (`references/1-ecosystem/repo-boundaries.md`). |
| A deployed app's frontend (or engine) starts being consumed by an *external* repo | Re-frame as Layout 06 — the deployed→distributed reframe (`references/1-ecosystem/repo-boundaries.md`). |

## Open questions the skill should always re-ask

Even with a clear layout, some questions are project-specific and must be asked every time — the ALWAYS-ask list is owned by `references/01_question-flow.md` § "Special — never assume, always ask".
