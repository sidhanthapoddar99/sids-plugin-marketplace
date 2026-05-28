# Decision tree

Maps the question-flow answers (`01_question-flow.md`) onto a layout and the major cross-cutting decisions. Consult this AFTER the questions are answered, not before.

## Layout selection

The **first cut** is *deployed vs distributed* — does the repo run the product, or publish a package an external host runs? Most repos are deployed (Layouts 01–05). If the deliverable is a package a separate host consumes, it's Layout 06 regardless of how many backends/frontends it has internally.

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

- multiple backends → coordinate via Postgres / Redis Streams / HTTP (see the layout's *more-than-one-backend* section)
- multiple frontends sharing UI/types/styles → `packages/` workspaces (pnpm + turborepo)
- many small services each with their own boundary/deploy cadence → the mesh end of the spectrum (the signal you may be approaching Layout 03 or 05)

See `references/repo-setup/layouts/02_multi-app-monorepo.md`.

## Per-layout defaults

| Layout | Workspace tool | Compose layout | `ctl` shape |
|---|---|---|---|
| 01 single app / service | none | optional `docker/` | bare entrypoint, few subcommands |
| 02 multi-app monorepo | none; pnpm + turborepo when multiple frontends share code | `docker/` profiled base + `--config` overlays; `docker/<svc>/` per service at the mesh end | full subcommand set; language-aware (migrate, sqlx-prepare, test, …); dispatches to per-app builds |
| 03 polyrepo + aggregator | n/a | only the aggregator repo has compose (image-based, no build) | aggregator owns `ctl up app edge --config=prod`; each service repo has its own `ctl` |
| 04 ML | uvenv | none typically | `ctl train`, `ctl eval`, `ctl serve` |
| 05 infra orchestrator | go (the orchestrator binary itself) | `docker/<mode>/` tree | go binary at root |
| 06 embeddable package + reference host | pnpm/bun workspace (package + reference `apps/web`) | optional — only for the reference host's deps | `ctl dev` runs the reference host; `ctl build` builds the package; `ctl publish` ships it |

## Per-layout cross-cutting decisions

### Where does code live? (`app/` vs `src/`)

`src/` is **not** universal — it's an ecosystem convention. The rule:

| Code kind | Inner layout | `src/`? | Why |
|---|---|---|---|
| Python backend / service (FastAPI, Flask, worker) | `<name>/app/` | **No** | Run, never packaged into a wheel — `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for no benefit |
| Frontend (Vite / React / Next) | `<name>/src/` | **Yes** | Bundler / tooling convention |
| Distributable package / library | `<name>/src/<pkg>/` | **Yes** | src-layout forces clean packaging — the one place it earns its keep |

**Nesting follows app count:**

- **One app total** → top-level `./<name>/` (name is free)
- **More than one app** → group all under `apps/<name>/`

| Layout | Path pattern |
|---|---|
| 01 (single backend service) | `./<name>/app/` — top-level, flat, no `src/` |
| 01 (single distributable tool/lib) | `./<name>/src/<pkg>/` — top-level, src-layout |
| 02 (backends) | `apps/<backend-lang>/app/` per backend (flat) |
| 02 (frontends) | `apps/<frontend>/src/` per frontend |
| 02 (shared packages) | `packages/<pkg>/src/<pkg>/` per shared package |
| 03 | per individual repo — apply the same rule inside each |
| 04 (ML) | `apps/<project>/src/<pkg>/` for the package, or flat scripts; ML tooling varies |
| 05 | `apps/<service>/app|src/` per service; orchestrator binary at `cchain/` or similar |
| 06 | the **product** package in `packages/<pkg>/src/` (published, src-layout); the **reference host** in `apps/web/src/`; optional BFF in `apps/api/app/` |

**Never loose code at repo root.** Always inside a service/app (or package) folder. One-liner: **flat `app/` for run-services, `src/` for frontends and packages, nothing loose in root.**

### `apps/` vs `packages/` — three categories, not two

The common framing is "`apps/` = deployables, `packages/` = internal shared code." That's incomplete: it has no slot for a repo whose *deliverable is a package an external host runs*. Split into **three**:

| Category | Lives in | Built/shipped as | React (if UI) | Versioned + published? |
|---|---|---|---|---|
| **Deployable app** | `apps/<name>/` | a running process / image you deploy | bundled (owns its React) | no |
| **Internal shared lib** | `packages/<name>/` | consumed *in-repo* by sibling apps via the workspace | bundled by the consuming app | no (workspace-internal) |
| **Published product package** | `packages/<name>/` (the product) | an artifact installed by an **external** repo (npm / PyPI) | **`peerDependency`** — the host owns the React instance | **yes** — `package.json` `exports`, build tooling (tsup/rollup), semver |

The third category is the one the two-category model erases. When the deliverable is the package itself (Layout 06), the repo's `apps/web` is a **reference host** — a dev harness — not the product. See `references/architecture/frontend/embeddable-package-and-reference-host.md` for the publishing mechanics (exports, peerDeps, single-artifact bundling) and the embedding-seams (inversion-of-control) pattern.

### Where does `config.yaml` live?

| Layout | Path |
|---|---|
| 01 | `./<name>/config.yaml` (single service, top-level) |
| 02 | `apps/<service>/config.yaml` per backend (frontend optional) |
| 03 | inside each repo, next to its service |
| 04 (ML) | `configs/<experiment>.yaml` (per-experiment) |
| 05 | per-service inside `apps/`; orchestrator config in its own folder |

**Never `config.yaml` at repo root.** Root has only `.env` / `.env.example`.

### Where do env vars live?

| Variable type | Location |
|---|---|
| Backend secrets, DB creds, shared infra ports | Root `.env` |
| Frontend-public build vars (`VITE_*`, `NEXT_PUBLIC_*`) | `apps/<frontend>/.env` (per frontend) |
| Per-experiment hyperparameters (ML) | `configs/<experiment>.yaml` |
| Production overrides | `.env.production` (compose `env_file`) |
| Local overrides | `.env.local`, `config.local.yaml` (gitignored) |

See `references/repo-setup/env-and-config/env-precedence.md` for the load order (root → per-service → real env wins).

### What compose structure does the layout need?

Two axes (see `references/repo-setup/runtime/docker-compose-structure.md`): **profiles** (which services) and **`--config` overlays** (how they run). Default set for Layout 02:

- `compose.yaml` — profiled base: data layer = no profile (always up); apps `profiles: [app]`; edge `profiles: [edge]`. No host ports.
- `compose.expose.yaml` — `--config=expose`: publish host ports (`ctl dev` layers it for the data core)
- `compose.prod.yaml` — `--config=prod`: image tags, resource limits, `.env.production`
- `compose.traefik.yaml` — `--config=traefik`: external Traefik network + labels on the edge

So `ctl up` = data core, `ctl up app` = +apps, `ctl up app edge --config=prod` = production. Single app (Layout 01) often needs only `compose.yaml` (+ `compose.expose.yaml`). ML (Layout 04) often needs no compose. Infra orchestrator (Layout 05) uses `docker/<mode>/compose.yaml` per mode (singlenode/multinode/prod) — see `references/repo-setup/runtime/complex-setups.md`.

### Python flow per layout

| Layout | Python flow |
|---|---|
| 01 | `pyproject.toml` + `uv.lock` + `uv sync` |
| 02 | `pyproject.toml` + `uv.lock` per Python backend |
| 03 | per-repo, modern flow |
| 04 (ML) | `requirements.txt` + uvenv global env (different on purpose) |
| 05 | `pyproject.toml` + `uv.lock` per Python service |

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

| Case | Tokens file |
|---|---|
| 02, single frontend | `apps/frontend/src/styles/tokens.css` |
| 02, multiple frontends | `packages/styles/src/tokens.css` (shared); each app imports |

### Docs location

| Layout | Docs |
|---|---|
| 01, 02, 04, 05 | in-repo `docs/` via documentation-template (`/docs-init`) |
| 03 polyrepo | separate `<product>-docs` repo |

## Escalation rules

These decisions only apply once a project crosses a complexity threshold:

| Trigger | Action |
|---|---|
| `ctl` shell dispatcher grows past ~150 lines or needs structured state across compose runs | Move orchestration to a Go binary (Layout 05; see `references/repo-setup/runtime/complex-setups.md`). |
| A single app grows a second app (backend or frontend) | Migrate Layout 01 → 02: introduce `apps/`, move the existing app under `apps/<name>/`. |
| Within Layout 02, frontends start sharing code | Introduce `pnpm-workspace.yaml` + `turbo.json` + `packages/` — still Layout 02. |
| Within Layout 02, services grow independent deploy cadences/boundaries | The mesh end of Layout 02; if they need separate repos, escalate to Layout 03. |
| `requirements.txt` flow grows reproducibility needs | Migrate Layout 04-style → 01-style with `pyproject.toml` + `uv.lock`. |
| Two repos start sharing env vars | Introduce a Layout 03 aggregator repo. |
| A deployed app's frontend (or engine) starts being consumed by an *external* repo | Re-frame as Layout 06: the consumed part becomes a published `packages/<pkg>/` (peerDeps, `exports`), the current app demotes to a reference host. |

## Open questions the skill should always re-ask

Even with a clear layout, these are project-specific and must be asked:

1. **Deployed vs distributed** — does this repo *run* the product, or *publish a package* an external host runs? If distributed → Layout 06 (the repo's own app is a reference host, not the product).
2. **Sibling repos** — does this repo expect another repo to be cloned next to it?
3. **External services** — Traefik present? Self-hosted Postgres elsewhere? Cloud DB?
4. **Deployment surface** — single target, multiple (WSL dev / bare server / cloud)?
5. **Open source vs private** — affects CI/CD defaults (GitHub Actions vs none).
6. **Theming** — both modes (default) or marketing-page light-only?
7. **Build-time env vars** — every `VITE_*` / `NEXT_PUBLIC_*` must be confirmed: is it safe to bake into the bundle?
