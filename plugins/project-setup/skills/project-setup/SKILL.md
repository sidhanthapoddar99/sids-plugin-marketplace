---
name: project-setup
description: Sid's architectural conventions — the single authority for EVERY structural, layout, placement, or convention decision in a repo, greenfield or established. Trigger eagerly whenever a task touches repo structure or project conventions, even mid-task and even when the user doesn't phrase it as a question — bootstrapping / auditing / restructuring a repo; monorepo vs polyrepo; adding or splitting services or frontends; "where does X go / where should this file live / app/ or src/"; deployed app vs published package (embeddable UI / SDK + reference host); choosing a database (SQLite vs Postgres, Redis vs in-memory, Mongo / Neo4j / Seaweed); docker-compose layout — profile-less base + standalone configs + `.m.` modifiers, expose tiers — and the `ctl` dispatcher (`ctl dev` / `ctl up`) with its scripts; root `.env` vs per-service `config.yaml`, secrets matrix, frontend env isolation (`VITE_` / `NEXT_PUBLIC_` leaks); frontend architecture and conventions — Vite proxy / nginx pair, pnpm / turborepo workspaces, shared ui package, shadcn, `tokens.css` design tokens, light/dark theming, and the primitive-first styling discipline that OVERRIDES the frontend-design skill in established repos; modularity caps (500/300 lines, folders by feature); Python flow (`uv sync` for apps, `uvenv` for ML); Alembic migrations (incl. the raw-SQL shim); production serving (gunicorn / uvicorn workers, worker recycling, healthchecks, graceful shutdown, resource limits, migrations-on-deploy); ML cloud orchestration (dstack, SkyPilot, spot + checkpoints, inference autoscaling, remote GPU dev via SSH + VS Code, agent SSH access); mobile (Kotlin / Swift) and desktop (Tauri / Electron); tooling (lefthook, mise, VS Code debugger); polyrepo deploy aggregators. Any mention of `apps/`, `packages/`, `infra/`, `data/`, `docker/`, `tokens.css`, `config.yaml`, `compose.yaml`, `.env.example`, `.mise.toml`, or `ctl` is a trigger. When in doubt, trigger — undertriggering is the failure mode. SKIP only for pure in-file work (debugging runtime behaviour, editing function bodies, test output, application logic); defer dstack CLI operation to the sibling `dstack` skill and docs-site content to the `agent-ks` plugin (ex `documentation-guide`).
---

# project-setup

You are inside Sid's `project-setup` plugin. Your job is to **own every architectural / structural decision** for a repo: layout, config split, env, docker (profile-less compose: a standalone `config` + `.m.` modifiers), design tokens, modularity, ML orchestration, mono- vs poly-repo, where each file should live.

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
5. **Compose lives in `docker/`, profile-less, on two axes:** an optional standalone **`config`** (`compose.<name>.yaml` that *replaces* base — `data`, `prod`; ≤1 per run) plus stackable **`.m.` modifiers** (`compose.m.<name>.yaml`, applied as `--modifier expose,traefik`; expose is tiered `expose` / `expose_data` / `expose_all`). Base declares the whole stack: no profiles, port-less, bind-mounts only. Profiles are a rare advanced escalation (`complex-setups.md`), not the default. Mechanics: `references/repo-setup/runtime/docker-overview.md`.
6. **One `ctl` dispatcher at repo root — the only entrypoint.** `ctl dev` = local host loop (apps on host, hot reload, auto-starts the data core if any). `ctl up [config] [--modifier "a,b"]` = the containerised stack; **bare `ctl up` in a TTY is interactive** (pick → plan → confirm, printing the exact flag command so CI stays 100% flag-driven). There is **no `ctl prod` verb** — production is `ctl up prod`. `down`/`ps`/`logs`/`shell`/`status`/`setup`/`migrate` round it out. A **thin wrapper** over `docker compose`, a process runner, and `scripts/*.sh`; the name `ctl` is swappable. Full surface: `references/repo-setup/runtime/script-overview.md` + `script-usage.md`.
7. **README documents the three startup paths**, and **each service/app ships its own `README.md`** for its host dev loop (see `references/repo-setup/readme-three-paths.md`).
8. **Examples are evidence, not gospel.** They evolved at different times. Cite them, do not blindly copy.
9. **Conventions must outlive the session — they live in the project's `CLAUDE.md`.** A skill only reaches the agent that loads it; the project CLAUDE.md reaches every agent, every session. Bootstrap and suggest flows write the hard rules there from `assets/snippets/claude/CLAUDE.md.template` (including the styling-discipline block — see ⚠️ below); the project CLAUDE.md then takes precedence over everything else.

**Ecosystem-dependent typed defaults — pick the right branch, deviate per the rule:**

10. **Where code lives follows the ecosystem — there is no blanket `src/`:**
   - **Python backend/service** (run, not packaged) → `<name>/app/` — **no `src/`**. It's run, never built into a wheel; `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for zero benefit. Matches the official full-stack FastAPI template (`backend/app/`).
   - **Frontend** (Vite/React/Next) → `<name>/src/` — `src/` per bundler convention.
   - **Distributable package/library** → `<name>/src/<pkg>/` — src-layout earns its keep, forcing clean packaging.
   - *Deviate when:* the ecosystem's own tooling expects a different layout — follow the tool.
11. **Nesting follows service count:**
    - **One service total** (just a backend, or just a frontend) → top-level `./<name>/` (name is free: `api`/`backend`/`web`/`frontend`/…), with `app/` or `src/` inside.
    - **More than one service** (backend + frontend, or several backends) → group all under `apps/<name>/` (`apps/api/app/`, `apps/web/src/`, …).
    - One-liner: **flat for run-services, `src/` for frontends and packages, nothing loose in root.**

Each service/app folder owns its `README.md`, dependency manifest (`requirements.txt` / `pyproject.toml` / `package.json`), `config.yaml`, and `Dockerfile`.

## ⚠️ VERY IMPORTANT — frontend styling precedence

**If the repo has a `tokens.css` + a ui package, the styling discipline (`references/architecture/frontend/styling-discipline.md`) OVERRIDES any general design guidance — including the `frontend-design` skill. Do not follow "be bold / unique / never converge" instructions in feature work. Convergence IS the design.**

**Whenever you bootstrap such a repo (or apply changes in suggest mode), WRITE the "Styling discipline" block from `assets/snippets/claude/CLAUDE.md.template` into the project's CLAUDE.md** (names resolved to the project's real ui package and paths). In read-only audit mode, don't edit — flag a missing block as a **red** finding instead. This is not optional polish — CLAUDE.md is always in context while skills are not, so the project memory file is the only thing that makes the discipline hold for every future agent, including parallel workers and weak models that never load this skill. The project CLAUDE.md then takes precedence over everything.

`frontend-design` has exactly one legitimate slot: the explicit design-exploration pass (day one, establishing brand/tokens/primitives, or a sanctioned redesign). Its output must graduate into tokens + primitive variants before the pass ends. Everywhere else, it is noise — ignore it.

## Two workflows

### A — wholesale bootstrap / audit / suggest (user invokes `/ps-setup`)

Walk the full flow: decision tree → question flow → layout → cross-cutting conventions → propose → apply.

### B — single architectural decision (the majority case — user is mid-work)

A surgical version: identify the smallest set of references that bear on the question, surface the convention, explain the trade-off, propose an action. Route via the annotated **file map** at the bottom of this document — read the 1–3 files whose comments match the decision, nothing more. Don't drag the user through the whole question flow when they're asking "where does this `init.sql` belong" — answer from `references/architecture/database/infra-vs-data-folder.md`, cite the rule, suggest the placement.

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

For every layout, the same cross-cutting conventions apply (layout-specific adjustments documented per-layout). The annotated **file map** at the bottom of this document is the single index — walk the convention areas the project actually has (`repo-setup/env-and-config`, `repo-setup/runtime`, `repo-setup/tooling`, `architecture/{backend,frontend,database,production,ml-orchestration,platform,modularity}`, `integrations/`) and read the files whose comments match. Ordering hints:

- `repo-setup/runtime/` — **start at `overview.md`**, the one map of how mise + `ctl` + docker + env interact; the other runtime files hang off it.
- `architecture/ml-orchestration/` — start at `overview.md`; dstack work also composes with the sibling `dstack` plugin's skill.
- `architecture/frontend/` — any styling surface **must include `styling-discipline.md`** (see ⚠️ above).
- Docs are a handoff, not our work — see `integrations/docs-integration.md` (the docs plugin is now `agent-ks`, scaffolded via `/agent-ks-init`).
- Versions in all references are illustrative — check latest stable and let the user pick.

### Step 5 — propose, then act

- For `/ps-setup` (init): present the proposed tree as text, list every file you'll create, then ask once before writing. Drop snippets from `assets/snippets/` where they fit. **Always create the project `CLAUDE.md` from `assets/snippets/claude/CLAUDE.md.template`** — fill the hard rules with this project's real names, and include the styling-discipline block whenever the repo has a frontend. CLAUDE.md is the convention carrier for every future agent (skills don't always load; CLAUDE.md always does) — a bootstrap that skips it defeats the plugin.
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
4. If the repo has `tokens.css` + a ui package, also run the styling-discipline greps from `references/architecture/frontend/styling-discipline.md` (arbitrary values / sizes and weights outside the CLAUDE.md allowlist / raw `var()` in feature code) and check that the project `CLAUDE.md` contains the styling-discipline block — a missing block is a **red** finding, because nothing else holds the line for future agents.
5. For `audit`, stop there.
6. For `suggest`, follow with a proposed remediation plan — what to add, what to rename, what to split.

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

**Running autonomously (no user available to ask)?** Don't guess silently and don't stall: take the convention default, proceed, and record every assumption explicitly in the proposal and the generated CLAUDE.md so the user can correct it later. An explicit wrong assumption is recoverable; a silent one becomes drift.

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
│   ├── runtime/                   # the execution triad: mise + ctl + docker (firm: one entrypoint; profile-less standalone config + compose.m.*)
│   │   ├── overview.md            # ★ START HERE: how mise + ctl + docker + env interact (the ONE map); others link here
│   │   ├── mise.md                # .mise.toml version contract + bare-name PATH (versions illustrative)
│   │   ├── docker-overview.md # docker/ layout + path discipline; profile-less: standalone config (replaces base) vs compose.m.* modifiers + expose tiers
│   │   ├── docker-details.md      # bind-mounts + data/ layout (nested pgdata trick) + internal-vs-host ports + YAML anchors
│   │   ├── script-overview.md     # the ctl/scripts model (common/ libs + dev|container|config workers): dev vs up, thin wrapper, <category>/<name>.sh convention, the 2 custom bodies
│   │   ├── script-usage.md        # command surface + skeleton + interactive ctl up (plan/--list) + scripts/*.sh map + setup(bootstraps deps)/status
│   │   ├── script-alternatives.md # opting out of mise/docker/uv→uvenv·venv·poetry/bun→pnpm·npm: which .sh lines to edit (tools are swappable defaults)
│   │   ├── no-data-core.md        # DATA_SVCS=() topology swap: apps-as-core for a DB-less project (the analogue of script-alternatives)
│   │   └── complex-setups.md      # profiles as the advanced escalation + multi-mode docker/<mode>/ trees + escalate ctl → a Go binary (→ Layout 05)
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
│   │   ├── design-tokens.md       # tokens.css owns brand values only; no hex/px in component CSS; typography = stock Tailwind scales + CLAUDE.md allowlist
│   │   ├── styling-discipline.md  # ★ HARD RULES: primitive-first feature code, tokens only, stock vocabulary + allowlist policy, fold-on-second, frontend-design precedence → goes into project CLAUDE.md
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
    ├── docs-integration.md        # docs handoff — plugin renamed documentation-guide → agent-ks (/agent-ks-init); file text predates the rename
    ├── claude-folder.md           # .claude/ stays empty initially; CLAUDE.md template guidance
    └── examples-index.md          # REAL repos to cite (atheneum/NeuraSutra/plane/chimere/uvenv) — never invent paths

assets/snippets/                   # fragments to drop into a target repo (NOT read as guidance)
├── frontend/{tokens,globals,light-dark}.css, vite-proxy.config.ts
├── docker/compose.yaml (profile-less base, whole stack) + compose.{data,prod}.yaml (standalone configs) + compose.m.{expose,expose_data,expose_all,traefik}.yaml (modifiers)
├── infra/nginx.conf
├── python/{alembic-shim.py, alembic_helpers.py}
├── env/{env.example.template, mise.toml.example}
├── scripts/ctl (thin router → repo root) + common/{_lib.sh,_select.sh} (shared: colors/help/dc+discovery/guards/picker) + workers dev/* container/* config/*
├── claude/CLAUDE.md.template     # hard rules + NON-NEGOTIABLE styling-discipline block — ALWAYS instantiated on bootstrap
└── README.md                      # snippet index: what each fragment is + where it drops

commands/ps-setup.md               # the /ps-setup slash command (init | audit | suggest)
```

## See also

- Snippets: `assets/snippets/` for fragments to drop in (see the snippet README for the index).
- Slash command: `commands/ps-setup.md` (the user-facing entrypoint).
- Examples cited: `references/integrations/examples-index.md`.
