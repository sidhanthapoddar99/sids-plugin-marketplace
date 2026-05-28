# Decision tree

Maps the question-flow answers (`01_question-flow.md`) onto a topology and the major cross-cutting decisions. Consult this AFTER the questions are answered, not before.

## Topology selection

The **first cut** is *deployed vs distributed* — does the repo run the product, or publish a package an external host runs? Most repos are deployed (01–08). If the deliverable is a package a separate host consumes, it's Topology 09 regardless of how many backends/frontends it has internally.

```
STEP 1 — does this repo RUN the product, or PUBLISH a package an external host runs?
├── Distributed — deliverable is a published package; the repo's own app (if any) is just a reference host
│   └── → Topology 09 (embeddable package + reference host)   [skip Step 2]
└── Deployed — the repo runs the product → continue to Step 2

STEP 2 — (deployed only) pick the deployed topology:
Is this a single repo, or multiple repos working together?
├── Single repo (monorepo or single-app)
│   ├── Is there a frontend?
│   │   ├── No frontend
│   │   │   ├── Is it an ML project (training, experiments, notebooks)?
│   │   │   │   ├── Yes → Topology 07 (ML project)
│   │   │   │   └── No  → Topology 01 (single-app)
│   │   │   └── Multiple backends in different languages, coordinating?
│   │   │       ├── Yes → Topology 03 (multi-backend microservices) — frontend optional
│   │   │       └── Many small backends, each own boundary → Topology 05 (microservices mesh)
│   │   ├── Single frontend
│   │   │   ├── Single backend → Topology 02 (mono 1be + 1fe)
│   │   │   └── Multiple backends → Topology 03 (multi-backend microservices)
│   │   └── Multiple frontends sharing UI/types/styles
│   │       └── → Topology 04 (multi-frontend workspaces)
│   └── Is there an infra orchestrator (multi-node, complex compose graph)?
│       └── Yes → Topology 08 (infra orchestrator) — usually wraps one of the above
└── Multiple repos working together
    └── → Topology 06 (polyrepo with deploy aggregator)
```

## Per-topology defaults

| Topology | Workspace tool | Compose layout | `ctl` shape |
|---|---|---|---|
| 01 single-app | none | optional `docker/` | bare entrypoint, few subcommands |
| 02 mono 1be+1fe | none (or pnpm if frontend is heavy) | `docker/` w/ full deployment-mode set | full subcommand set |
| 03 multi-backend | none | `docker/` w/ full deployment-mode set | language-aware subcommands (migrate, sqlx-prepare, test, …) |
| 04 multi-frontend | pnpm + turborepo (default for Vite/React); bun workspaces ok | `docker/` w/ full set | dispatches to per-app builds |
| 05 microservices mesh | none — each backend is independent | per-service compose under `docker/<svc>/` | wrapper-of-wrappers |
| 06 polyrepo + aggregator | n/a | only aggregator repo has compose (image-based, no build) | aggregator owns `ctl prod`; each service repo has own `ctl` |
| 07 ML | uvenv | none typically | `ctl train`, `ctl eval`, `ctl serve` |
| 08 infra orchestrator | go (the orchestrator binary itself) | `docker/<mode>/` tree | go binary at root |
| 09 embeddable package + reference host | pnpm/bun workspace (package + reference `apps/web`) | optional — only for the reference host's deps | `ctl dev` runs the reference host; `ctl build` builds the package; `ctl publish` ships it |

## Per-topology cross-cutting decisions

### Where does code live? (`app/` vs `src/`)

`src/` is **not** universal — it's an ecosystem convention. The rule:

| Code kind | Inner layout | `src/`? | Why |
|---|---|---|---|
| Python backend / service (FastAPI, Flask, worker) | `<name>/app/` | **No** | Run, never packaged into a wheel — `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for no benefit |
| Frontend (Vite / React / Next) | `<name>/src/` | **Yes** | Bundler / tooling convention |
| Distributable package / library | `<name>/src/<pkg>/` | **Yes** | src-layout forces clean packaging — the one place it earns its keep |

**Nesting follows service count:**

- **One service total** → top-level `./<name>/` (name is free)
- **More than one service** → group all under `apps/<name>/`

| Topology | Path pattern |
|---|---|
| 01 (single backend service) | `./<name>/app/` — top-level, flat, no `src/` |
| 01 (single distributable tool/lib) | `./<name>/src/<pkg>/` — top-level, src-layout |
| 02 | `apps/<backend>/app/` (flat) and `apps/<frontend>/src/` |
| 03 | `apps/<backend-lang>/app/` per backend; `apps/<frontend>/src/` |
| 04 | `apps/<app>/src/` per frontend; `packages/<pkg>/src/<pkg>/` per shared package |
| 05 | `apps/<service>/app/` per Python service (or `src/` if it's a frontend) |
| 06 | per individual repo — apply the same rule inside each |
| 07 (ML) | `apps/<project>/src/<pkg>/` for the package, or flat scripts; ML tooling varies |
| 08 | `apps/<service>/app|src/` per service; orchestrator binary at `cchain/` or similar |
| 09 | the **product** package in `packages/<pkg>/src/` (published, src-layout); the **reference host** in `apps/web/src/`; optional BFF in `apps/api/app/` |

**Never loose code at repo root.** Always inside a service/app (or package) folder. One-liner: **flat `app/` for run-services, `src/` for frontends and packages, nothing loose in root.**

### `apps/` vs `packages/` — three categories, not two

The common framing is "`apps/` = deployables, `packages/` = internal shared code." That's incomplete: it has no slot for a repo whose *deliverable is a package an external host runs*. Split into **three**:

| Category | Lives in | Built/shipped as | React (if UI) | Versioned + published? |
|---|---|---|---|---|
| **Deployable app** | `apps/<name>/` | a running process / image you deploy | bundled (owns its React) | no |
| **Internal shared lib** | `packages/<name>/` | consumed *in-repo* by sibling apps via the workspace | bundled by the consuming app | no (workspace-internal) |
| **Published product package** | `packages/<name>/` (the product) | an artifact installed by an **external** repo (npm / PyPI) | **`peerDependency`** — the host owns the React instance | **yes** — `package.json` `exports`, build tooling (tsup/rollup), semver |

The third category is the one the two-category model erases. When the deliverable is the package itself (Topology 09), the repo's `apps/web` is a **reference host** — a dev harness — not the product. See `references/architecture/frontend/embeddable-package-and-reference-host.md` for the publishing mechanics (exports, peerDeps, single-artifact bundling) and the embedding-seams (inversion-of-control) pattern.

### Where does `config.yaml` live?

| Topology | Path |
|---|---|
| 01 | `./<name>/config.yaml` (single service, top-level) |
| 02 | `apps/<backend>/config.yaml`, `apps/<frontend>/config.yaml` (optional) |
| 03 | `apps/backend-<lang>/config.yaml` per backend |
| 04 | `apps/<app>/config.yaml` per app |
| 05 | `apps/<service>/config.yaml` per service |
| 06 | inside each repo, next to its service |
| 07 | `configs/<experiment>.yaml` (per-experiment) |
| 08 | per-service inside `apps/`; orchestrator config in its own folder |

**Never `config.yaml` at repo root.** Root has only `.env` / `.env.example`.

### Where do env vars live?

| Variable type | Location |
|---|---|
| Backend secrets, DB creds, shared infra ports | Root `.env` |
| Frontend-public build vars (`VITE_*`, `NEXT_PUBLIC_*`) | `apps/<frontend>/.env` (per frontend) |
| Per-experiment hyperparameters (ML) | `configs/<experiment>.yaml` |
| Production overrides | `.env.production` (compose `env_file`) |
| Local overrides | `.env.local`, `config.local.yaml` (gitignored) |

### What compose modes does the topology need?

Default set for Topology 02–05:

- `compose.yaml` — base (no host ports, internal network)
- `compose.database-only.yaml` — postgres + redis only
- `compose.dev.yaml` — overlay that adds host ports
- `compose.prod.yaml` — production overrides
- `compose.traefik.yaml` — overlay for external Traefik network
- `compose.no-ports.yaml` — overlay for prod hosts behind a reverse proxy

Single-app (Topology 01) often needs only `compose.yaml` + `compose.dev.yaml`.

ML (Topology 07) often needs no compose at all.

Infra orchestrator (Topology 08) typically has `docker/<mode>/compose.yaml` per mode (singlenode/multinode/prod), not overlay files.

### Python flow per topology

| Topology | Python flow |
|---|---|
| 01 | `pyproject.toml` + `uv.lock` + `uv sync` |
| 02 | `pyproject.toml` + `uv.lock` per backend |
| 03 | `pyproject.toml` + `uv.lock` per Python backend |
| 04 | `pyproject.toml` + `uv.lock` per Python app |
| 05 | `pyproject.toml` + `uv.lock` per service |
| 06 | per-repo, modern flow |
| 07 | `requirements.txt` + uvenv global env (different on purpose) |
| 08 | `pyproject.toml` + `uv.lock` per Python service |

### Frontend tooling per topology

| Topology | Frontend tool |
|---|---|
| 01 | n/a |
| 02 | Vite + bun (or Next/Astro if circumstances demand) |
| 03 | Same as 02; single frontend |
| 04 | Vite + pnpm + turborepo (default); shared `packages/ui` etc. |
| 05 | Same as 02/04 depending on count |
| 06 | per-repo |
| 07 | none typically |
| 08 | rarely; if present, same as 02 |

### Design tokens location

| Topology | Tokens file |
|---|---|
| 02 single-frontend | `apps/frontend/src/styles/tokens.css` |
| 04 multi-frontend | `packages/styles/src/tokens.css` (shared); each app imports |

### Docs location

| Topology | Docs |
|---|---|
| 01–05, 07, 08 | in-repo `docs/` via documentation-template (`/docs-init`) |
| 06 polyrepo | separate `<product>-docs` repo |

## Escalation rules

These decisions only apply once a project crosses a complexity threshold:

| Trigger | Action |
|---|---|
| `ctl` shell dispatcher grows past ~150 lines or needs structured state across compose runs | Move orchestration to a Go binary (Topology 08 pattern). |
| Single-backend monorepo grows a second backend | Migrate Topology 02 → 03; rename `apps/backend/` → `apps/backend-<primary-lang>/`. |
| Single-frontend monorepo grows a second frontend that shares any code | Migrate Topology 02 → 04; introduce `pnpm-workspace.yaml` + `turbo.json` + `packages/`. |
| `requirements.txt` flow grows reproducibility needs | Migrate Topology 07-style → 01-style with `pyproject.toml` + `uv.lock`. |
| Two repos start sharing env vars | Introduce Topology 06 aggregator repo. |
| A deployed app's frontend (or engine) starts being consumed by an *external* repo | Re-frame as Topology 09: the consumed part becomes a published `packages/<pkg>/` (peerDeps, `exports`), the current app demotes to a reference host. |

## Open questions the skill should always re-ask

Even with a clear topology, these are project-specific and must be asked:

1. **Deployed vs distributed** — does this repo *run* the product, or *publish a package* an external host runs? If distributed → Topology 09 (the repo's own app is a reference host, not the product).
2. **Sibling repos** — does this repo expect another repo to be cloned next to it?
3. **External services** — Traefik present? Self-hosted Postgres elsewhere? Cloud DB?
4. **Deployment surface** — single target, multiple (WSL dev / bare server / cloud)?
5. **Open source vs private** — affects CI/CD defaults (GitHub Actions vs none).
6. **Theming** — both modes (default) or marketing-page light-only?
7. **Build-time env vars** — every `VITE_*` / `NEXT_PUBLIC_*` must be confirmed: is it safe to bake into the bundle?
