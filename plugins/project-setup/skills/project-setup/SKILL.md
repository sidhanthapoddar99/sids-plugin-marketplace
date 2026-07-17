---
name: project-setup
description: Opinionated architectural conventions — the single authority for EVERY structural, layout, placement, or convention decision in a repo, greenfield or established, at every altitude (L1 ecosystem / L2 repo / L3 app / L4 feature). Trigger eagerly whenever a task touches repo structure or project conventions, even mid-task and even when the user doesn't phrase it as a question — bootstrapping / auditing / restructuring a repo; monorepo vs polyrepo, repo boundaries, where docs live (in-repo `docs/` vs a separate docs repo); adding or splitting services or frontends; `apps/` grouping topology (flat vs plane-grouped `apps/server/` + `apps/client/`), workspace rooting (repo root vs frontend group folder), package placement scope; "where does X go / where should this file live / app/ or src/"; deployed app vs published package (embeddable UI / SDK + reference host); admin vs user identity planes (two-plane backend split, the neutral `apps/db` migrations owner); core backend vs BFF; choosing a database (SQLite vs Postgres, Redis vs in-memory, Mongo / Neo4j / Seaweed); migration style (Alembic autogenerate vs raw-SQL three-file shim); docker-compose layout — profile-less base + standalone configs + `.m.` modifiers, expose tiers — and the `ctl` dispatcher (`ctl dev` / `ctl up`) with its `scripts/` tree and conformance floor; root hygiene (root-as-index, orchestration-only root manifest, `.gitignore` doctrine); root `.env` vs per-service `config.yaml`, secrets matrix, frontend env isolation (`VITE_` / `NEXT_PUBLIC_` leaks); frontend architecture and conventions — Vite proxy / nginx pair, pnpm / turborepo workspaces, shared ui package, shadcn, `tokens.css` design tokens, light/dark theming, the intra-app `src/` skeleton (`layout/ features/ pages/ api/ stores/` — the api-layer rule, thin pages, type placement), and the primitive-first styling discipline that OVERRIDES the frontend-design skill in established repos; modularity + structural tripwires (500/300 line caps, ~8–10 features → domain layer, ~10 files → subdivide a feature, folders by feature, adapter modules for N providers); Python flow (`uv sync` for apps, `uvenv` for ML); production serving (gunicorn / uvicorn workers, worker recycling, healthchecks, graceful shutdown, resource limits, migrations-on-deploy); ML cloud orchestration (dstack, SkyPilot, spot + checkpoints, inference autoscaling, remote GPU dev via SSH + VS Code, agent SSH access); mobile (Kotlin / Swift) and desktop (Tauri / Electron); tooling (lefthook, mise, VS Code debugger); polyrepo deploy aggregators. Any mention of `apps/`, `packages/`, `infra/`, `data/`, `docker/`, `tokens.css`, `config.yaml`, `compose.yaml`, `.env.example`, `.gitignore`, `.mise.toml`, or `ctl` is a trigger. When in doubt, trigger — undertriggering is the failure mode. SKIP only for pure in-file work (debugging runtime behaviour, editing function bodies, test output, application logic); defer dstack CLI operation to the sibling `dstack` skill and docs-site content to the `agent-ks` plugin (ex `documentation-guide`).
---

# project-setup

You are inside the `project-setup` plugin. Your job is to **own every architectural / structural decision** for a repo: layout, config split, env, docker (profile-less compose: a standalone `config` + `.m.` modifiers), design tokens, modularity, ML orchestration, mono- vs poly-repo, where each file should live.

**Every structural decision has an altitude.** The skill's spine is the four-level model in `references/levels/00_altitude-model.md` — L1 ecosystem (across repos) / L2 repo / L3 app / L4 feature — with one charter per level routing to the topical references. Classify the altitude first; ties go up. The same file also holds the five recurring principles and the master tripwire table everything else cites.

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
6. **One `ctl` dispatcher at repo root — the only entrypoint.** `ctl dev` = local host loop (apps on host, hot reload, auto-starts the data core if any). `ctl up [config] [--modifier "a,b"]` = the containerised stack; **bare `ctl up` in a TTY is interactive** (pick → plan → confirm, printing the exact flag command so CI stays 100% flag-driven). There is **no `ctl prod` verb** — production is `ctl up prod`. `down`/`ps`/`logs`/`shell`/`status`/`setup`/`migrate` round it out. A **thin wrapper** over `docker compose`, a process runner, and `scripts/*.sh`; the name `ctl` is swappable. **Installed by copying `assets/snippets/scripts/` verbatim and adapting by deletion — never authored from prose, never collapsed into a single file** (the conformance floor: `references/repo-setup/runtime/script-overview.md` § conformance floor). Full surface: `references/repo-setup/runtime/script-overview.md` + `script-usage.md`.
7. **README documents the three startup paths**, and **each service/app ships its own `README.md`** for its host dev loop (see `references/repo-setup/readme-three-paths.md`).
8. **Examples are evidence, not gospel.** They evolved at different times. Cite them, do not blindly copy.
9. **The root is an index, not a runtime.** No loose code or entry files at the repo root; a root manifest (when the ecosystem demands one) is orchestration-only — zero runtime deps, no source; the JS workspace roots at the repo root only in a JS-only repo (polyglot → the frontend group folder); `.gitignore` is curated per-ecosystem. Exceptions are recorded choices. See `references/repo-setup/root-and-hygiene.md`.
10. **Structure is versioned: variants are recorded, tripwires have numbers.** Every variant pick (grouping topology, workspace rooting, backend role, migration owner, sanctioned exceptions) is recorded in the project CLAUDE.md; every structural threshold (master table in `references/levels/00_altitude-model.md`) obligates the restructure or a recorded deferral. **Audits compare the repo against its recorded choices** — an unusual shape with a recorded choice is a variant; a missing record is the finding.
11. **Conventions must outlive the session — they live in the project's `CLAUDE.md`.** A skill only reaches the agent that loads it; the project CLAUDE.md reaches every agent, every session. Bootstrap and suggest flows write the hard rules there from `assets/snippets/claude/CLAUDE.md.template` (including the structure-contract block and the styling-discipline block — see ⚠️ below); the project CLAUDE.md then takes precedence over everything else.

**Ecosystem-dependent typed defaults — pick the right branch, deviate per the rule:**

12. **Where code lives follows the ecosystem — there is no blanket `src/`:**
   - **Python backend/service** (run, not packaged) → `<name>/app/` — **no `src/`**. It's run, never built into a wheel; `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for zero benefit. Matches the official full-stack FastAPI template (`backend/app/`).
   - **Frontend** (Vite/React/Next) → `<name>/src/` — `src/` per bundler convention.
   - **Distributable package/library** → `<name>/src/<pkg>/` — src-layout earns its keep, forcing clean packaging.
   - *Deviate when:* the ecosystem's own tooling expects a different layout — follow the tool.
13. **Nesting follows service count:**
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

A surgical version: identify the smallest set of references that bear on the question, surface the convention, explain the trade-off, propose an action. Route by **altitude first**: classify the decision's level (`references/levels/00_altitude-model.md`), open that level's charter — it names the decision axis and the owning reference — or jump straight via the annotated **file map** at the bottom of this document when the target file is obvious. Read the 1–3 files whose comments match the decision, nothing more. Don't drag the user through the whole question flow when they're asking "where does this `init.sql` belong" — that's L2 → `references/architecture/database/infra-vs-data-folder.md`, cite the rule, suggest the placement.

Pattern for B:

1. Classify the altitude — L1 ecosystem / L2 repo / L3 app / L4 feature (ties go up).
2. Route: the level charter (`references/levels/`) or the file map → the 1–3 references that apply.
3. State the convention + the why.
4. Propose the change (with file paths).
5. Ask before editing if the change is non-trivial; if the decision picked a variant or crossed a tripwire, record it in the project CLAUDE.md.

Both workflows draw from the same references library — A is the all-in-one tour, B is the targeted lookup.

## Workflow A — wholesale

Workflow A walks the levels **top-down** — L1 → L2 → L3, installing L4 as doctrine — and each level has a named output: **L1** → the repo set + each repo's role; **L2** → the tree + runtime + the recorded variant choices; **L3** → per-app skeletons; **L4** → the CLAUDE.md blocks installed (never asked).

### Step 1 — read the spine

Open `references/levels/00_altitude-model.md` (levels, principles, tripwires) and `references/00_decision-tree.md` (the L2 layout picker: answers → layout + key decisions).

### Step 2 — run the question flow

Open `references/01_question-flow.md`. It's level-ordered — run it in order. Ask the user only the questions whose answer you can't reliably infer from the current repo or conversation. Skip what's already answered. Stop and confirm if any answer is ambiguous.

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

For every layout, the same cross-cutting conventions apply (layout-specific adjustments documented per-layout). The **level charters** (`references/levels/02_repo.md`, `03_app.md`, `04_feature.md`) enumerate every decision area per level with its owning reference; the annotated **file map** at the bottom of this document is the exhaustive index — walk the convention areas the project actually has (`repo-setup/env-and-config`, `repo-setup/runtime`, `repo-setup/root-and-hygiene.md`, `repo-setup/tooling`, `architecture/{backend,frontend,database,production,ml-orchestration,platform,modularity}`, `integrations/`) and read the files whose comments match. Ordering hints:

- `repo-setup/runtime/` — **start at `overview.md`**, the one map of how mise + `ctl` + docker + env interact; the other runtime files hang off it.
- `architecture/ml-orchestration/` — start at `overview.md`; dstack work also composes with the sibling `dstack` plugin's skill.
- `architecture/frontend/` — any styling surface **must include `styling-discipline.md`** (see ⚠️ above).
- Docs are a handoff, not our work — see `integrations/docs-integration.md` (the docs plugin is now `agent-ks`, scaffolded via `/agent-ks-init`).
- Versions in all references are illustrative — check latest stable and let the user pick.

### Step 5 — propose, then act

- For `/ps-setup` (init): present the proposed tree as text, list every file you'll create, then ask once before writing. Drop snippets from `assets/snippets/` where they fit. **Install the runtime layer by copying, never authoring**: `cp -r "${CLAUDE_PLUGIN_ROOT}/assets/snippets/scripts" ./scripts && mv ./scripts/ctl ./ctl && chmod +x ./ctl`, then adapt by deletion (conformance floor: `references/repo-setup/runtime/script-overview.md`); generate `.gitignore` from `assets/snippets/env/gitignore.template`, keeping only the ecosystems present. **Always create the project `CLAUDE.md` from `assets/snippets/claude/CLAUDE.md.template`** — resolve the hard rules AND the structure-contract block (recorded variant choices, skeletons with this project's real names, tripwire numbers, escalation pointer), and include the styling-discipline block whenever the repo has a frontend. CLAUDE.md is the convention carrier for every future agent (skills don't always load; CLAUDE.md always does) — a bootstrap that skips any of its blocks has not delivered the conventions at all.
- For `/ps-setup audit`: produce a drift report. Read-only. Do not change files.
- For `/ps-setup suggest`: produce a proposal for the current repo. Don't change files; if the user wants to apply, they can re-run with init flow on top.

## Audit / suggest mode

When the mode is `audit` or `suggest`:

1. Read the current repo structure (top-level + `apps/*`, `packages/*`, `docker/`, `infra/`, `data/`, `scripts/`) **and the project CLAUDE.md** — its structure-contract block holds the recorded variant choices, which are the audit baseline. **A missing structure contract is itself a red finding**; without one, audit against the defaults and say so.
2. Identify the closest layout **and the recorded variants**. Compare the repo against its **recorded choices**, not just the canonical trees — a plane-grouped topology or a root-manifest exception with a recorded choice is conformant; the same shape unrecorded is drift.
3. Walk the levels (each charter ends with its audit list):
   - **L1** (`references/levels/01_ecosystem.md`): siblings/roles stated in CLAUDE.md when siblings exist; cross-repo sharing pinned; one docs home.
   - **L2** (`levels/02_repo.md`): root contract (loose code at root, runtime deps in a root manifest, polyglot repo with a root-rooted workspace, missing/incomplete `.gitignore`, tracked `.env` = red); **`ctl` conformance floor** — `_lib.sh` sourced, `scripts/common/` present, verbs routed to workers; a single-file `ctl` with inlined bodies = **red**; compose axes (ports in base, profiles without a recorded escalation); env split; README three paths.
   - **L3** (`levels/03_app.md`): **count** feature folders per app (~8–10 tripwire) and files per feature folder (~10) — crossings with no recorded deferral = findings; frontend skeleton presence (`pages/`, `api/` in a grown app); local `ui`/`styles` duplicating workspace packages = red; migration ownership (two backends sharing DDL, migrations-on-boot in a two-backend repo = red).
   - **L4** (`levels/04_feature.md`): the mechanical greps — server calls outside `api/`, and (when `tokens.css` + a ui package exist) the styling-discipline greps from `references/architecture/frontend/styling-discipline.md`; file caps; a missing styling block in CLAUDE.md = **red**, because nothing else holds the line for future agents.
4. For each convention area, list findings tagged by level:
   - **Matches** (green) — what's already aligned
   - **Drift** (yellow) — minor deviations
   - **Missing** (red) — conventions not present
5. For `audit`, stop there.
6. For `suggest`, follow with a proposed remediation plan — what to add, what to rename, what to split — and batch the moves into a consolidation window (`references/levels/00_altitude-model.md` § evolution) rather than dribbling renames across PRs.

Never edit files in `audit` mode. In `suggest` mode, only edit after explicit confirmation.

## When to ask vs assume

| Situation | Ask? |
|---|---|
| Repo cardinality (mono vs poly, # backends, # frontends) | Always ask if not stated; never infer from file presence alone. |
| Identity planes (operator/admin vs end-user) | Always ask when an admin surface exists — it drives backend count, the migrations owner, and exposure (`references/architecture/backend/two-plane-split.md`). |
| Grouping topology + workspace rooting (2+ apps) | Ask when more than one variant fits; record the pick in the project CLAUDE.md. |
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
├── levels/                        # ★ THE SPINE — classify a decision's altitude FIRST, then route via its charter
│   ├── 00_altitude-model.md       # the 4 levels + binding times, routing rule, 5 principles, MASTER TRIPWIRE TABLE, evolution machinery
│   ├── 01_ecosystem.md            # L1: repo cardinality + boundaries, sibling roles, docs placement, cross-repo sharing/contracts
│   ├── 02_repo.md                 # L2: layout, grouping topology, BFF axis, root contract, runtime triad, env, DB engines, deployment
│   ├── 03_app.md                  # L3: app/package internals — skeletons, domains, migration style + owner, shared-lib placement
│   └── 04_feature.md              # L4: feature folders, types/DTOs, api internals, styling, caps — delivered via CLAUDE.md blocks, never asked
├── 00_decision-tree.md            # the L2 layout picker: answers → layout + app/-vs-src/ + config/env placement
├── 01_question-flow.md            # level-ordered questions (L1→L2→L3; L4 never asked); ALWAYS-ask list
│
├── repo-setup/                    # INTENT: how the repo is wired, run, configured, deployed
│   ├── layouts/                   # pick ONE based on the decision tree
│   │   ├── 01_single-app.md           # exactly one app — CLI/lib/lone backend or lone frontend
│   │   ├── 02_multi-app-monorepo.md   # 2+ apps in one repo (any # be/fe); grouping topology (flat/plane-grouped/hybrid) + core-vs-BFF axis; router for multi-backend/-frontend/mesh
│   │   ├── 03_polyrepo-with-aggregator.md # services in separate repos + a -deploy aggregator
│   │   ├── 04_ml-project.md           # uvenv + requirements.txt, no compose; pulls in ml-orchestration/
│   │   ├── 05_infra-orchestrator.md   # compose tree driven by a Go CLI
│   │   └── 06_embeddable-package-and-reference-host.md  # product = published package; apps/web is a dev harness
│   ├── runtime/                   # the execution triad: mise + ctl + docker (firm: one entrypoint; profile-less standalone config + compose.m.*)
│   │   ├── overview.md            # ★ START HERE: how mise + ctl + docker + env interact (the ONE map); others link here
│   │   ├── mise.md                # .mise.toml version contract + bare-name PATH (versions illustrative)
│   │   ├── docker-overview.md # docker/ layout + path discipline; profile-less: standalone config (replaces base) vs compose.m.* modifiers + expose tiers
│   │   ├── docker-details.md      # bind-mounts + data/ layout (nested pgdata trick) + internal-vs-host ports + YAML anchors
│   │   ├── script-overview.md     # the ctl/scripts model (common/ libs + dev|container|config workers): dev vs up, thin wrapper, <category>/<name>.sh convention, the 2 custom bodies
│   │   ├── script-usage.md        # command surface + skeleton + interactive ctl up (plan/--list) + scripts/*.sh map + setup(bootstraps deps)/status
│   │   ├── script-alternatives.md # opting out of mise/docker/uv→uvenv·venv·poetry/bun→pnpm·npm: which .sh lines to edit (tools are swappable defaults)
│   │   ├── multi-stack.md         # two+ repos' stacks sharing one docker network: external networks, project-unique service names, cross-stack URLs
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
│   ├── root-and-hygiene.md        # ★ root-as-index: orchestration-only root manifest, workspace rooting (JS-only vs polyglot), single-package containment + exceptions, .gitignore doctrine
│   └── readme-three-paths.md      # root README contract + per-service READMEs (host dev loop)
│
├── architecture/                  # INTENT: what's inside / how it's built
│   ├── backend/                   # backend-language flow — app/ vs src/, uv vs uvenv, migrations (Python today)
│   │   ├── pyproject-uv-sync-for-apps.md  # run-service (flat app/, uv sync) vs distributable (src/<pkg>/)
│   │   ├── requirements-uvenv-for-ml.md   # ML: requirements.txt + uvenv global env (different on purpose)
│   │   ├── alembic-default.md     # Alembic init recipe + daily flow + migrations-in-Docker (entrypoint)
│   │   ├── alembic-with-raw-sql.md    # raw-.sql + 3-line shim, for multi-lang schema consumers
│   │   ├── when-not-alembic.md    # when another migration tool / no tool is right
│   │   └── two-plane-split.md     # separate admin/user backends: the decision (security posture), one-DB ownership, the neutral apps/db migrations owner
│   ├── frontend/                  # Vite/React + theming + multi-frontend + embeddable
│   │   ├── single-frontend.md     # the default apps/<frontend>/src/ layout (Layout 02)
│   │   ├── intra-app-structure.md # ★ inside src/: the hard skeleton (layout/components/features/pages/hooks/api/lib/stores), api-layer rule, type placement, subdivision tripwires, package internals
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
│       ├── domain-grouping-tripwire.md  # ★ the layer ABOVE features: ~8–10 folders → app/<domain>/<feature>/; naming (ownership nouns), feature seams, adapter-modules, DTO placement
│       └── extract-on-third-use.md    # rule of three before extracting a shared helper
│
└── integrations/                 # INTENT: peripheral / external-tool handoffs
    ├── docs-integration.md        # docs handoff — plugin renamed documentation-guide → agent-ks (/agent-ks-init); file text predates the rename
    ├── claude-folder.md           # .claude/ stays empty initially; CLAUDE.md template guidance
    └── examples-index.md          # the examples REGISTRY — the user's own real repos to cite; never invent paths

assets/snippets/                   # fragments to drop into a target repo (NOT read as guidance)
├── frontend/{tokens,globals,light-dark}.css, vite-proxy.config.ts
├── docker/compose.yaml (profile-less base, whole stack) + compose.{data,prod}.yaml (standalone configs) + compose.m.{expose,expose_data,expose_all,traefik}.yaml (modifiers)
├── infra/nginx.conf
├── python/{alembic-shim.py, alembic_helpers.py}
├── env/{env.example.template, mise.toml.example, gitignore.template}
├── scripts/ctl (thin router → repo root) + common/{_lib.sh,_select.sh} (shared: colors/help/dc+discovery/guards/picker) + workers dev/* container/* config/*
├── claude/CLAUDE.md.template     # hard rules + structure-contract block (recorded variants, skeletons, tripwires, escalation) + NON-NEGOTIABLE styling-discipline block — ALWAYS instantiated on bootstrap, every placeholder resolved
└── README.md                      # snippet index: what each fragment is + where it drops

commands/ps-setup.md               # the /ps-setup slash command (init | audit | suggest)
```

## See also

- Snippets: `assets/snippets/` for fragments to drop in (see the snippet README for the index).
- Slash command: `commands/ps-setup.md` (the user-facing entrypoint).
- Examples cited: `references/integrations/examples-index.md`.
