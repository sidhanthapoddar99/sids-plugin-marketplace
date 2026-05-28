---
name: project-setup
description: Use when making any architectural, structural, layout, or convention decision about a repo — bootstrapping a new one, restructuring an existing one, adding or splitting services, picking databases or orchestrators, or deciding where a file or folder belongs. Equally for greenfield init and for modifying established codebases. Covers monorepo vs polyrepo, single vs multi backend / frontend, deployed application vs distributed/published package (embeddable UI / SDK + reference host), the `apps/` / `packages/` / `infra/` / `data/` / `docker/` folder split, root `.env` vs per-service `config.yaml`, secrets matrix, docker-compose profiles (service selection) + `--config` overlays, the `ctl` control dispatcher (`ctl dev` host loop + `ctl up [profile] [--config]`, no separate prod verb), design tokens + light/dark, modularity caps (500/300 lines, folders by feature), ML cloud orchestration (dstack, SkyPilot, spot + checkpoints, inference autoscaling, remote GPU dev via SSH + VS Code, agent SSH access), Python flow (`uv sync` for apps vs `uvenv` + `requirements.txt` for ML), Alembic + raw-SQL shim pattern, production serving (gunicorn/uvicorn workers, worker recycling, graceful shutdown, healthchecks, resource limits, migrations-on-deploy), mobile (Kotlin/Swift), desktop (Tauri / Electron), lefthook, VS Code debugger setup, `.mise.toml`, polyrepo deploy aggregators, Go-CLI infra orchestrators. Triggers on "create a project", "init a repo", "scaffold a monorepo", "bootstrap", "audit my layout", "restructure this repo", "where should X go", "where does X belong", "is this the right place for", "split this backend", "add a backend", "add a frontend", "add a service", "pick a database", "Postgres vs Mongo", "SQLite or Postgres", "do I need Postgres", "in-memory or Redis", "do I need Redis", "app/ or src/", "src layout", "where does the code go", "monorepo or polyrepo", "deployed app or package", "distributed package", "publish a package", "embeddable component", "library vs app", "SDK package", "reference host", "where to put .env", "single .env or per-service", "config.yaml location", "VITE_ leak", "frontend env isolation", "design tokens", "tokens.css", "light/dark mode", "shadcn setup", "multi-frontend", "pnpm workspaces", "turborepo", "compose layout", "deployment modes", "bind-mount data", "./dev wrapper", "ctl dispatcher", "control script", "dev vs deploy", "process-compose", "dev script", "setup script", "mise.toml", "alembic", "uv sync vs requirements", "uvenv", "dstack", "SkyPilot", "spot training", "checkpoint training", "remote GPU dev", "agent SSH access", "gunicorn workers", "how many workers", "worker recycling", "max-requests", "uvicorn workers", "production serving", "graceful shutdown", "healthcheck endpoint", "liveness readiness", "resource limits", "migrations on deploy", "production checklist", "Tauri or Electron", "iOS Android repo layout", "lefthook", "VS Code launch.json", "polyrepo aggregator", "deploy repo", "docs folder", "documentation-template", `apps/`, `packages/`, `infra/`, `data/`, `docker/`, `tokens.css`, `config.yaml`, `.env.example`, `.mise.toml`, `compose.yaml`. SKIP when the user is debugging runtime behaviour, editing function bodies, reviewing test output, writing application logic inside an existing file, or operating purely inside the dstack CLI surface (defer to the sibling `dstack` skill) or editing documentation-template content (defer to the sibling `documentation-guide` skill) — this skill owns the structural / placement / convention side, not the in-file work.
---

# project-setup

You are inside Sid's `project-setup` plugin. Your job is to **own every architectural / structural decision** for a repo: layout, config split, env, docker (compose profiles + `--config` overlays), design tokens, modularity, ML orchestration, mono- vs poly-repo, where each file should live.

This applies to **two situations equally**:

1. **Bootstrapping a new repo** — `/ps-setup` init
2. **Modifying an existing repo** — any time the user asks "should I add X", "where does Y belong", "is this the right place for Z", "split this", "introduce a package", "move compose into `docker/`", "switch to a multi-frontend workspace", "add a second backend", "pick a database", "set up remote GPU dev"

Don't wait to be asked for a wholesale bootstrap. Engage when **any** decision in the architectural surface area is being considered.

Goal: stop the user inventing fresh patterns each time. Encode the conventions; apply them; explain the trade-offs when the user pushes back.

## Strong defaults (and when to deviate)

These are the conventions to apply by default. Most are **firm** — their value *is* the standardization, so don't relax them without a real reason. A few are **ecosystem-dependent typed defaults** — apply the right branch for the stack, and deviate only per the stated rule. This is a decision guide, not a rulebook; preach judgment, but standardize where standardizing is the whole point.

**Firm — keep these:**

1. **No single ideal structure exists.** The right layout depends on shape questions. Always consult the question flow before proposing anything.
2. **If you don't have information, ASK.** Do not presume. Common unknowns: sibling repos, whether the project is ML or app, whether the frontend exposes any backend URLs, deployment targets, theming requirements.
3. **Root holds only config + README + folders — never loose code.** No executable entry file or stray module directly in the repo root; keep the root clean. *(Only exception: project types that genuinely demand a root entry file — e.g. some editor extensions like a VS Code extension.)*
4. **Per-service `config.yaml`, root `.env`.** Root `.env` holds shared/common vars only. Each backend owns its own `config.yaml`. Frontends have their own env scope (`VITE_*` / `NEXT_PUBLIC_*`) — backend secrets must never leak there.
5. **Compose lives in `docker/`**, split on three axes (each a distinct compose mechanism): **profiles** (which services run — the data core has no profile and is always up; apps opt in via `profiles: [app]` / `[edge]`), at most one **`--config=prod`** (a full alternate deployment config in `compose.prod.yaml`), and stackable **`.m.` modifiers** (`compose.m.<name>.yaml`, applied as `--expose` / `--traefik`). Base is port-less; profiles do ~90% of the work because dev runs on the host. Bind-mounts only. See `references/repo-setup/runtime/docker-overview.md`.
6. **One `ctl` dispatcher at repo root.** `ctl dev` runs the local host loop (apps on host, hot reload, auto-starts the data core). `ctl up [profile…] [--config=prod] [--<modifier>…]` runs the containerised stack — profiles select services, one optional config picks a deployment config, `.m.` modifiers stack on top, all auto-discovered; there is **no `ctl prod` verb** (production is `ctl up app edge --config=prod`). `down`/`ps`/`logs` manage containers; `status`/`setup`/`migrate` round it out. It is a **thin wrapper** delegating to `docker compose`, a process runner (`process-compose`/`mprocs`), and `scripts/*.sh` — the dispatcher is the public API, callable bare via mise PATH. Name `ctl` is swappable.
7. **README documents the three startup paths**, and **each service/app ships its own `README.md`** for its host dev loop (see `references/repo-setup/readme-three-paths.md`).
8. **Examples are evidence, not gospel.** They evolved at different times. Cite them, do not blindly copy.

**Ecosystem-dependent typed defaults — pick the right branch, deviate per the rule:**

9. **Where code lives follows the ecosystem — there is no blanket `src/`:**
   - **Python backend/service** (run, not packaged) → `<name>/app/` — **no `src/`**. It's run, never built into a wheel; `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for zero benefit. Matches the official full-stack FastAPI template (`backend/app/`).
   - **Frontend** (Vite/React/Next) → `<name>/src/` — `src/` per bundler convention.
   - **Distributable package/library** → `<name>/src/<pkg>/` — src-layout earns its keep, forcing clean packaging.
   - *Deviate when:* the ecosystem's own tooling expects a different layout — follow the tool.
10. **Nesting follows service count:**
    - **One service total** (just a backend, or just a frontend) → top-level `./<name>/` (name is free: `api`/`backend`/`web`/`frontend`/…), with `app/` or `src/` inside.
    - **More than one service** (backend + frontend, or several backends) → group all under `apps/<name>/` (`apps/api/app/`, `apps/web/src/`, …).
    - One-liner: **flat for run-services, `src/` for frontends and packages, nothing loose in root.**

Each service/app folder owns its `README.md`, dependency manifest (`requirements.txt` / `pyproject.toml` / `package.json`), `config.yaml`, and `Dockerfile`.

## Two workflows

### A — wholesale bootstrap / audit / suggest (user invokes `/ps-setup`)

Walk the full flow: decision tree → question flow → layout → cross-cutting conventions → propose → apply.

### B — single architectural decision (user is in the middle of work)

A surgical version: identify the smallest set of references that bear on the question, surface the convention, explain the trade-off, propose an action. Don't drag the user through the whole question flow when they're asking "where does this `init.sql` belong" — answer from `references/architecture/database/infra-vs-data-folder.md`, cite the rule, suggest the placement.

Pattern for B:

1. Identify the decision (placement / split / pick / rename / introduce / remove).
2. Find the 1–3 references that apply.
3. State the convention + the why.
4. Propose the change (with file paths).
5. Ask before editing if the change is non-trivial.

Both workflows draw from the same references library — A is the all-in-one tour, B is the targeted lookup.

## Workflow A — wholesale

### Step 1 — read the decision tree

Open `references/00_decision-tree.md`. It maps question answers → layout + key decisions.

### Step 2 — run the question flow

Open `references/01_question-flow.md`. Run through it in order. Ask the user only the questions whose answer you can't reliably infer from the current repo or conversation. Skip what's already answered. Stop and confirm if any answer is ambiguous.

### Step 3 — pick a layout

Based on the answers, pick a layout from `references/repo-setup/layouts/`:

| # | File | When |
|---|---|---|
| 01 | `01_single-app.md` | Exactly one runnable app — a CLI, library, lone backend, or lone frontend. |
| 02 | `02_multi-app-monorepo.md` | Two or more apps in one repo — any mix of backends + frontends. 1be+1fe is the common case; multi-backend coordination, multi-frontend `packages/`, and the mesh end are points on the same spectrum (count is a parameter, not a separate layout). |
| 03 | `03_polyrepo-with-aggregator.md` | Each service in its own repo + a `-deploy` aggregator repo. |
| 04 | `04_ml-project.md` | uvenv global env, `requirements.txt`, no frontend, no compose. |
| 05 | `05_infra-orchestrator.md` | Compose tree driven by a Go CLI. |
| 06 | `06_embeddable-package-and-reference-host.md` | The deliverable is a *published package* (UI component / SDK / headless engine) an external host mounts; `apps/web` is a reference host, not the product. |

If the user's shape doesn't cleanly match one, name the closest two and ask which they want — or document the hybrid explicitly.

### Step 4 — apply the cross-cutting conventions

For every layout, the same conventions apply (with layout-specific adjustments documented per-layout). Consult:

- `references/repo-setup/env-and-config/` — root `.env`, per-service `config.yaml`, env precedence (root → per-service → real env wins), frontend env isolation, build-time vs runtime, `${VAR}` interpolation, secrets matrix
- `references/repo-setup/runtime/` — the execution triad (mise + `ctl` + docker). **Start at `runtime/overview.md`** for how they interact; then `docker-overview.md` (profiles vs `--config` vs `compose.m.*`), `script-overview.md` + `script-usage.md` (the `ctl`/`scripts` model and its command surface), `mise.md`, and `complex-setups.md` (multi-mode + binary orchestrator)
- `references/architecture/backend/` — `uv` for apps, `uvenv` for ML, Alembic conventions
- `references/architecture/frontend/` — Vite/proxy/nginx pair, multi-frontend workspaces, design tokens, light/dark
- `references/architecture/database/` — **choosing a database** (SQLite vs Postgres, in-process memory vs Redis), `infra/` vs `data/`, postgres/redis/sqlite/seaweed/mongo/neo4j conventions (versions illustrative — check latest)
- `references/architecture/production/` — app server + workers (gunicorn/uvicorn worker count, recycling, timeouts, preload; per-language concurrency models), production-readiness checklist (liveness/readiness, graceful shutdown, resource limits, migrations-on-deploy, logging)
- `references/architecture/ml-orchestration/` — dstack (composes with the dstack plugin's skill) / SkyPilot / spot+checkpoints / inference autoscaling / remote dev via SSH+VS Code / agent SSH access / CI/CD for ML
- `references/architecture/modularity/` — 500/300 line caps, folders by feature, extract on third use
- `references/architecture/platform/` — mobile (Kotlin/Swift), desktop (Tauri default, Electron alt)
- `references/repo-setup/tooling/` — lefthook (pre-commit), VS Code debugger setup
- `references/repo-setup/runtime/mise.md` — version pinning contract (versions illustrative — check latest)
- `references/integrations/claude-folder.md` — `.claude/` conventions (empty by default)
- `references/repo-setup/readme-three-paths.md` — README contract
- `references/integrations/docs-integration.md` — defer all docs work to the `documentation-guide` skill; `/docs-init` to scaffold
- `references/repo-setup/tooling/ci-cd-future.md` — placeholder, GitHub Actions / Vault notes
- `references/integrations/examples-index.md` — pointers to the real-world examples (atheneum, NeuraSutra, plane, chimere)

### Step 5 — propose, then act

- For `/ps-setup` (init): present the proposed tree as text, list every file you'll create, then ask once before writing. Drop snippets from `assets/snippets/` where they fit.
- For `/ps-setup audit`: produce a drift report. Read-only. Do not change files.
- For `/ps-setup suggest`: produce a proposal for the current repo. Don't change files; if the user wants to apply, they can re-run with init flow on top.

## Audit / suggest mode

When the mode is `audit` or `suggest`:

1. Read the current repo structure (top-level + `apps/*`, `packages/*`, `docker/`, `infra/`, `data/`, `scripts/`).
2. Identify the closest layout.
3. For each convention area, compare the repo to the reference and list:
   - **Matches** (green) — what's already aligned
   - **Drift** (yellow) — minor deviations
   - **Missing** (red) — conventions not present
4. For `audit`, stop there.
5. For `suggest`, follow with a proposed remediation plan — what to add, what to rename, what to split.

Never edit files in `audit` mode. In `suggest` mode, only edit after explicit confirmation.

## When to ask vs assume

| Situation | Ask? |
|---|---|
| Repo cardinality (mono vs poly, # backends, # frontends) | Always ask if not stated; never infer from file presence alone. |
| Language mix | Ask; don't assume from `*.py` extensions (might be ML, might be app). |
| ML vs app project | Ask explicitly. The Python flow differs. |
| Sibling-repo dependencies | Always ask. Cannot infer from inside one repo. |
| Theme / dark mode requirement | Ask if frontend exists. Default both modes; opt out for marketing pages. |
| Deployment targets (WSL / bare server / cloud / Traefik present) | Ask before generating prod compose. |
| Build-time vs runtime for each env var | Walk through each `.env.example` line with the user. |
| Existing `.env` content (when auditing) | Do not read `.env` files — they contain secrets. Read `.env.example` only. |
| Image / runtime versions (postgres:?, redis:?, python:?) | Always — versions in this skill's references are illustrative. Check latest stable, surface options, let the user pick. |
| ML cloud orchestrator (dstack / SkyPilot / custom / none) | Always ask for ML projects. If dstack, also consult the `dstack` skill in the sibling plugin. |
| Remote dev / agent SSH access for ML projects | Always ask — different layout surface (`apps/cloud/`, `tasks/`, `scripts/cloud/`) |

## What you do not do

- Do not generate a full project template. Use snippets.
- Do not assume a workspace tool (`pnpm-workspace.yaml`, `turbo.json`) when a single-frontend project doesn't need one.
- Do not force ML projects into the app shape — Layout 04.
- Do not edit anything without showing the plan first and getting confirmation.
- Do not read `.env` files (secrets); `.env.example` is the contract.
- Do not invent file paths from training data — consult `references/integrations/examples-index.md` to cite real examples.

## File map — everything in this skill, annotated

Read the file whose comment matches the decision in front of you. Paths are relative to this skill folder (`skills/project-setup/`); snippet/command paths are relative to the plugin root.

```
references/
├── 00_decision-tree.md            # START HERE for layout: answers → layout + app/-vs-src/ + config/env placement
├── 01_question-flow.md            # the questions to ask before proposing (batched); ALWAYS-ask list
│
├── repo-setup/                    # INTENT: how the repo is wired, run, configured, deployed
│   ├── layouts/                   # pick ONE based on the decision tree
│   │   ├── 01_single-app.md           # exactly one app — CLI/lib/lone backend or lone frontend
│   │   ├── 02_multi-app-monorepo.md   # 2+ apps in one repo (any # be/fe); router for multi-backend/-frontend/mesh
│   │   ├── 03_polyrepo-with-aggregator.md # services in separate repos + a -deploy aggregator
│   │   ├── 04_ml-project.md           # uvenv + requirements.txt, no compose; pulls in ml-orchestration/
│   │   ├── 05_infra-orchestrator.md   # compose tree driven by a Go CLI (chimere)
│   │   └── 06_embeddable-package-and-reference-host.md  # product = published package; apps/web is a dev harness
│   ├── runtime/                   # the execution triad: mise + ctl + docker (firm: one entrypoint; profiles + --config + compose.m.*)
│   │   ├── overview.md            # ★ START HERE: how mise + ctl + docker + env interact (the ONE map); others link here
│   │   ├── mise.md                # .mise.toml version contract + bare-name PATH (versions illustrative)
│   │   ├── docker-overview.md # docker/ layout + path discipline; profiles (selection) vs --config configs vs compose.m.* modifiers
│   │   ├── docker-details.md      # bind-mounts + data/ layout (nested pgdata trick) + internal-vs-host ports + YAML anchors
│   │   ├── script-overview.md     # the ctl/scripts model: dev vs up, thin wrapper, the 2 custom bodies, why-host, 3 startup paths
│   │   ├── script-usage.md        # command surface + dispatcher skeleton + scripts/*.sh map + setup/status + host loop + startup commands
│   │   └── complex-setups.md      # multi-mode docker/<mode>/ trees + escalate ctl → a Go binary (→ Layout 05)
│   ├── env-and-config/            # the env/config split (a firm convention area)
│   │   ├── env-precedence.md          # where a value comes from & who wins: 3 tiers + root .env scope + .env.example + config.local.yaml
│   │   ├── per-service-config.md      # each backend's config.yaml + ${VAR} interpolation from root .env
│   │   ├── frontend-env-isolation.md  # SECURITY: build-time vs runtime + VITE_*/NEXT_PUBLIC_* must not leak secrets to the bundle
│   │   └── secrets-matrix.md          # dev / CI / prod / Vault — where secrets live, rotation
│   ├── tooling/                   # optional dev tooling + CI/CD
│   │   ├── lefthook.md            # pre-commit hooks (format/lint pre-commit, tests pre-push)
│   │   ├── vscode-debugger.md     # .vscode/launch.json etc. for the no-docker host path
│   │   └── ci-cd-future.md        # GitHub Actions templates; Vault-later notes (general app CI)
│   └── readme-three-paths.md      # root README contract + per-service READMEs (host dev loop)
│
├── architecture/                  # INTENT: what's inside / how it's built
│   ├── backend/                   # backend-language flow — app/ vs src/, uv vs uvenv, migrations (Python today)
│   │   ├── pyproject-uv-sync-for-apps.md  # run-service (flat app/, uv sync) vs distributable (src/<pkg>/)
│   │   ├── requirements-uvenv-for-ml.md   # ML: requirements.txt + uvenv global env (different on purpose)
│   │   ├── alembic-default.md     # Alembic init recipe + daily flow + migrations-in-Docker (entrypoint)
│   │   ├── alembic-with-raw-sql.md    # raw-.sql + 3-line shim, for multi-lang schema consumers (atheneum)
│   │   └── when-not-alembic.md    # when another migration tool / no tool is right
│   ├── frontend/                  # Vite/React + theming + multi-frontend + embeddable
│   │   ├── single-frontend.md     # the default apps/<frontend>/src/ layout (Layout 02)
│   │   ├── multi-frontend-workspaces.md   # pnpm+turborepo, packages/ (Layout 02, multi-frontend)
│   │   ├── shared-ui-package.md   # packages/ui, tailwind-config, types, services — what to share
│   │   ├── vite-proxy-nginx-pair.md   # dev Vite proxy → prod nginx; same /api/* contract
│   │   ├── api-prefix-routing.md  # all backend routes under /api/* (makes the proxy work)
│   │   ├── design-tokens.md       # tokens.css single source; no hex/px in component CSS
│   │   ├── light-dark-data-attr.md    # [data-theme="dark"] on <html>; both modes default
│   │   ├── shadcn-tailwind.md     # shadcn/ui + tailwind wired to var(--token)
│   │   ├── nextjs-astro-variants.md   # when Next (SSR) / Astro (static) instead of Vite
│   │   └── embeddable-package-and-reference-host.md  # embedding seams (host injects services/storage/theme); publishing a UI package (Layout 06)
│   ├── database/                  # WHICH engine + per-engine conventions
│   │   ├── choosing-a-database.md # SQLite vs Postgres; in-process memory vs Redis (pick the right floor)
│   │   ├── infra-vs-data-folder.md    # infra/ = committed config; data/ = gitignored bind-mount state
│   │   ├── postgres-conventions.md    # compose block, init scripts, extensions (versions illustrative)
│   │   ├── redis-conventions.md   # AOF, requirepass, db numbers, Streams (versions illustrative)
│   │   ├── sqlite-conventions.md  # WAL + busy_timeout + single-writer model; the right floor
│   │   └── mongodb-neo4j-seaweed.md   # Mongo/Neo4j/Kuzu/Seaweed/Meili + a "which to pick" table
│   ├── production/                # making it production-grade
│   │   ├── app-server-and-workers.md  # gunicorn/uvicorn worker count + RECYCLING + timeouts; per-lang model
│   │   └── production-readiness.md    # liveness/readiness, graceful shutdown, limits, migrations-on-deploy, checklist
│   ├── ml-orchestration/          # cloud GPU training/inference (Layout 04)
│   │   ├── overview.md            # START HERE for ML cloud; tools recognised, job shapes
│   │   ├── dstack.md              # DEFAULT orchestrator; defers to the sibling `dstack` skill for CLI
│   │   ├── skypilot.md            # alternative orchestrator
│   │   ├── custom-orchestrator.md # placeholder for a future bespoke tool (steer to dstack first)
│   │   ├── spot-instances-and-checkpoints.md  # surviving spot preemption; checkpoint-resumable training
│   │   ├── inference-autoscaling.md   # batch vs online serving; autoscale + redeploy on preemption
│   │   ├── remote-dev-ssh-vscode.md   # one-command remote GPU box + SSH + VS Code Remote + Claude on box
│   │   ├── agent-ssh-access.md    # how an agent operates a remote box safely (perms, CLAUDE.md brief)
│   │   └── cicd-for-ml.md         # cheap/medium/expensive pipeline tiers for ML
│   ├── platform/                  # non-web targets
│   │   ├── mobile.md              # native iOS (Swift) + Android (Kotlin) under apps/
│   │   └── desktop.md             # Tauri (default) / Electron; share packages/ with web
│   └── modularity/                # code-organisation rules (firm)
│       ├── file-size-caps.md      # 500 hard / 300 soft lines per file
│       ├── folders-by-feature.md  # group by feature (auth/, blocks/), not by kind (controllers/)
│       └── extract-on-third-use.md    # rule of three before extracting a shared helper
│
└── integrations/                 # INTENT: peripheral / external-tool handoffs
    ├── docs-integration.md        # defer docs to the documentation-guide skill; /docs-init handoff
    ├── claude-folder.md           # .claude/ stays empty initially; CLAUDE.md template guidance
    └── examples-index.md          # REAL repos to cite (atheneum/NeuraSutra/plane/chimere/uvenv) — never invent paths

assets/snippets/                   # fragments to drop into a target repo (NOT read as guidance)
├── frontend/{tokens,globals,light-dark}.css, vite-proxy.config.ts
├── docker/compose.yaml (profiled base) + compose.prod.yaml (--config) + compose.m.{expose,traefik}.yaml (modifiers)
├── infra/nginx.conf
├── python/{alembic-shim.py, alembic_helpers.py}
├── env/{env.example.template, mise.toml.example}
├── scripts/dev-wrapper.sh→ctl (thin dispatcher) + worker scripts (dev-host/setup/status/check-env/migrate/wait-for-health/test/build/clean).sh
├── claude/CLAUDE.md.template
└── README.md                      # snippet index: what each fragment is + where it drops

commands/ps-setup.md               # the /ps-setup slash command (init | audit | suggest)
```

## See also

- Snippets: `assets/snippets/` for fragments to drop in (see the snippet README for the index).
- Slash command: `commands/ps-setup.md` (the user-facing entrypoint).
- Examples cited: `references/integrations/examples-index.md`.
