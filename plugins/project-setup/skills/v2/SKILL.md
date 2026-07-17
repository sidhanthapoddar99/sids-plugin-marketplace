---
name: project-setup
description: Opinionated architectural conventions — the single authority for EVERY structural, layout, placement, or convention decision in a repo, greenfield or established, at every altitude (L1 ecosystem / L2 repo / L3 app / L4 feature). Trigger eagerly whenever a task touches repo structure or project conventions, even mid-task and even when the user doesn't phrase it as a question — bootstrapping / auditing / restructuring a repo; monorepo vs polyrepo, repo boundaries, where docs live (in-repo `docs/` vs a separate docs repo); adding or splitting services or frontends; `apps/` grouping topology (flat vs plane-grouped `apps/server/` + `apps/client/`), workspace rooting (repo root vs frontend group folder), package placement scope; "where does X go / where should this file live / app/ or src/"; deployed app vs published package (embeddable UI / SDK + reference host); admin vs user identity planes (two-plane backend split, the neutral `apps/db` migrations owner); core backend vs BFF; choosing a database (SQLite vs Postgres, Redis vs in-memory, Mongo / Neo4j / Seaweed); migration style (Alembic autogenerate vs raw-SQL three-file shim); docker-compose layout — profile-less base + standalone configs + `.m.` modifiers, expose tiers — and the `ctl` dispatcher (`ctl dev` / `ctl up`) with its `scripts/` tree and conformance floor; root hygiene (root-as-index, orchestration-only root manifest, `.gitignore` doctrine); root `.env` vs per-service `config.yaml`, secrets matrix, frontend env isolation (`VITE_` / `NEXT_PUBLIC_` leaks); frontend architecture and conventions — Vite proxy / nginx pair, pnpm / turborepo workspaces, shared ui package, shadcn, `tokens.css` design tokens, light/dark theming, the intra-app `src/` skeleton (`layout/ features/ pages/ api/ stores/` — the api-layer rule, thin pages, type placement), and the primitive-first styling discipline that OVERRIDES the frontend-design skill in established repos; modularity + structural tripwires (500/300 line caps, ~8–10 features → domain layer, ~10 files → subdivide a feature, folders by feature, adapter modules for N providers); Python flow (`uv sync` for apps, `uvenv` for ML); production serving (gunicorn / uvicorn workers, worker recycling, healthchecks, graceful shutdown, resource limits, migrations-on-deploy); ML cloud orchestration (`scripts/cloud/` wrappers over the provider CLI, spot + checkpoints, inference autoscaling, remote GPU dev via SSH + VS Code, agent SSH access); mobile (Kotlin / Swift) and desktop (Tauri / Electron); tooling (lefthook, mise, VS Code debugger); polyrepo deploy aggregators. Any mention of `apps/`, `packages/`, `infra/`, `data/`, `docker/`, `tokens.css`, `config.yaml`, `compose.yaml`, `.env.example`, `.gitignore`, `.mise.toml`, or `ctl` is a trigger. When in doubt, trigger — undertriggering is the failure mode. SKIP only for pure in-file work (debugging runtime behaviour, editing function bodies, test output, application logic); defer docs-site content to the `agent-ks` plugin (ex `documentation-guide`).
---

# project-setup

You are inside the `project-setup` plugin. Your job is to **own every architectural / structural decision** for a repo: layout, config split, env, docker (profile-less compose: a standalone `config` + `.m.` modifiers), design tokens, modularity, ML orchestration, mono- vs poly-repo, where each file should live.

**Every structural decision has an altitude.** The skill's spine is the four-level model in `references/00_altitude-model.md` — L1 ecosystem (across repos) / L2 repo / L3 app / L4 feature — with one charter per level routing to the topical references. Classify the altitude first; ties go up. The same file also holds the five recurring principles, the master tripwire table, and the **ownership map** (decision axis → owner file) that everything else cites.

This applies to **two situations equally**:

1. **Bootstrapping a new repo** — `/ps-setup` init
2. **Modifying an existing repo** — any time the user asks "should I add X", "where does Y belong", "is this the right place for Z", "split this", "introduce a package", "move compose into `docker/`", "switch to a multi-frontend workspace", "add a second backend", "pick a database", "set up remote GPU dev"

Don't wait to be asked for a wholesale bootstrap. Engage when **any** decision in the architectural surface area is being considered.

Goal: stop the user inventing fresh patterns each time. Encode the conventions; apply them; explain the trade-offs when the user pushes back.

## Strong defaults (and when to deviate)

These are the conventions to apply by default — a summary index, not the rule text. Each line links to the **one owner file** where the rule, its variants, its tripwire, and its audit check live; don't restate a rule from prose, open its owner. Most defaults are **firm** — their value *is* the standardization. A few are **ecosystem-dependent typed defaults** — apply the right branch for the stack.

**Firm — keep these:**

1. **No single ideal structure exists.** The right layout depends on shape questions. Always consult `references/01_question-flow.md` before proposing anything.
2. **If you don't have information, ASK.** Do not presume. Common unknowns: sibling repos, whether the project is ML or app, whether the frontend exposes any backend URLs, deployment targets, theming requirements.
3. **Root holds only config + README + folders — never loose code.** No executable entry file or stray module directly in the repo root. Owner: `references/2-repo/root-and-hygiene.md`. *(Only exception: project types that genuinely demand a root entry file — e.g. some editor extensions.)*
4. **Per-service `config.yaml`, root `.env`.** Root `.env` holds shared/common vars only; each backend owns its own `config.yaml`; frontends have their own env scope (`VITE_*` / `NEXT_PUBLIC_*`) — backend secrets must never leak there. Owners: `references/2-repo/env-and-config/env-precedence.md`, `per-service-config.md`, `frontend-env-isolation.md`.
5. **Compose lives in `docker/`, profile-less, on two axes:** an optional standalone **`config`** (`compose.<name>.yaml` that *replaces* base; ≤1 per run) plus stackable **`.m.` modifiers** (`compose.m.<name>.yaml`, `--modifier expose,traefik`; expose is tiered). Base declares the whole stack: no profiles, port-less, bind-mounts only. Owner: `references/2-repo/runtime/docker-overview.md`.
6. **One `ctl` dispatcher at repo root — the only entrypoint.** `ctl dev` = local host loop; `ctl up [config] [--modifier "a,b"]` = the containerised stack (bare `ctl up` in a TTY is interactive: pick → plan → confirm, printing the exact flag command so CI stays flag-driven). No `ctl prod` verb — production is `ctl up prod`. A thin wrapper over `docker compose` + a process runner + `scripts/*.sh`, **installed by copying `assets/snippets/scripts/` verbatim and adapting by deletion** (conformance floor). Owners: `references/2-repo/runtime/script-overview.md` + `script-usage.md`.
7. **README documents the three startup paths**, and **each service/app ships its own `README.md`**. Owner: `references/2-repo/readme-three-paths.md`.
8. **Examples are evidence, not gospel.** Cite them, do not blindly copy. Registry: `references/handoffs/examples-registry.md`; annotated trees: `references/5-examples/`.
9. **The root is an index, not a runtime.** No loose code at root; a root manifest is orchestration-only (zero runtime deps — tripwire T10); `.gitignore` is curated per-ecosystem; workspace rooting is part of the topology decision. Owners: `references/2-repo/root-and-hygiene.md` (root contract, `.gitignore`, T10), `references/2-repo/grouping-topology.md` (rooting).
10. **Structure is versioned: variants are recorded, tripwires have numbers.** Every variant pick is recorded in the project CLAUDE.md; every threshold (master table in `references/00_altitude-model.md`) obligates the restructure or a recorded deferral. **Audits compare the repo against its recorded choices** — an unrecorded unusual shape is the finding.
11. **Conventions must outlive the session — they live in the project's `CLAUDE.md`.** A skill only reaches the agent that loads it; the project CLAUDE.md reaches every agent, every session. Bootstrap/suggest write the hard rules there from `assets/snippets/claude/CLAUDE.md.template` (including the structure-contract block and the styling-discipline block — see ⚠️); the project CLAUDE.md then takes precedence. Owner: `references/handoffs/claude-folder.md`.

**Ecosystem-dependent typed defaults — pick the right branch, deviate per the rule:**

12. **Where code lives follows the ecosystem — there is no blanket `src/`:** Python backend/service (run, not packaged) → `<name>/app/`, **no `src/`** (`references/3-app/backend/app-skeleton.md`); frontend → `<name>/src/` (`references/3-app/frontend/app-skeleton.md`); distributable package → `<name>/src/<pkg>/` (`references/2-repo/layouts/06_embeddable-package.md`). *Deviate when* the ecosystem's own tooling expects a different layout.
13. **Nesting follows service count:** one service total → top-level `./<name>/`; more than one → group under `apps/<name>/`. Owner: `references/2-repo/grouping-topology.md`.

Each service/app folder owns its `README.md`, dependency manifest (`requirements.txt` / `pyproject.toml` / `package.json`), `config.yaml`, and `Dockerfile`.

## ⚠️ VERY IMPORTANT — frontend styling precedence

**If the repo has a `tokens.css` + a ui package, the styling discipline (`references/4-feature/styling-discipline.md`) OVERRIDES any general design guidance — including the `frontend-design` skill. Do not follow "be bold / unique / never converge" instructions in feature work. Convergence IS the design.**

**Whenever you bootstrap such a repo (or apply changes in suggest mode), WRITE the "Styling discipline" block from `assets/snippets/claude/CLAUDE.md.template` into the project's CLAUDE.md** (names resolved to the project's real ui package and paths). In read-only audit mode, don't edit — flag a missing block as a **red** finding. CLAUDE.md is always in context while skills are not, so the project memory file is the only thing that makes the discipline hold for every future agent, including parallel workers and weak models that never load this skill.

`frontend-design` has exactly one legitimate slot: the explicit design-exploration pass (day one, establishing brand/tokens/primitives, or a sanctioned redesign). Its output must graduate into tokens + primitive variants before the pass ends. Everywhere else, ignore it.

## Two workflows

### A — wholesale bootstrap / audit / suggest (user invokes `/ps-setup`)

Walk the full flow: decision tree → question flow → layout → cross-cutting conventions → propose → apply.

### B — single architectural decision (the majority case — user is mid-work)

A surgical version: identify the smallest set of references that bear on the question, surface the convention, explain the trade-off, propose an action. Route by **altitude first**: classify the decision's level (`references/00_altitude-model.md`), open that level's charter — it names the decision axis and the owning reference — or use the ownership map in the altitude model, or jump straight via the annotated **file map** at the bottom of this document. Read the 1–3 files whose comments match the decision, nothing more. Don't drag the user through the whole question flow when they're asking "where does this `init.sql` belong" — that's L2 → `references/2-repo/databases-provisioning.md`, cite the rule, suggest the placement.

Pattern for B:

1. Classify the altitude — L1 ecosystem / L2 repo / L3 app / L4 feature (ties go up).
2. Route: the level charter (`references/{1-ecosystem,2-repo,3-app,4-feature}/00_charter.md`), the ownership map, or the file map → the 1–3 references that apply.
3. State the convention + the why.
4. Propose the change (with file paths).
5. Ask before editing if the change is non-trivial; if the decision picked a variant or crossed a tripwire, record it in the project CLAUDE.md.

Both workflows draw from the same references library — A is the all-in-one tour, B is the targeted lookup.

## Workflow A — wholesale

Workflow A walks the levels **top-down** — L1 → L2 → L3, installing L4 as doctrine — and each level has a named output: **L1** → the repo set + each repo's role; **L2** → the tree + runtime + the recorded variant choices; **L3** → per-app skeletons; **L4** → the CLAUDE.md blocks installed (never asked).

### Step 1 — read the spine

Open `references/00_altitude-model.md` (levels, principles, tripwires, ownership map) and `references/02_decision-tree.md` (the L2 layout picker: answers → layout + key decisions).

### Step 2 — run the question flow

Open `references/01_question-flow.md`. It's level-ordered — run it in order. Ask the user only the questions whose answer you can't reliably infer from the current repo or conversation. Skip what's already answered. Stop and confirm if any answer is ambiguous.

### Step 3 — pick a layout

Based on the answers, pick a layout from `references/2-repo/layouts/`:

| # | File | When |
|---|---|---|
| 01 | `01_single-app.md` | Exactly one runnable app — a CLI, library, lone backend, or lone frontend. |
| 02 | `02_multi-app-monorepo.md` | Two or more apps in one repo — any mix of backends + frontends. 1be+1fe is the common case; multi-backend coordination, multi-frontend `packages/`, and the mesh end are points on the same spectrum. |
| 03 | `03_polyrepo-aggregator.md` | Each service in its own repo + a `-deploy` aggregator repo. |
| 04 | `04_ml-project.md` | uvenv global env, `requirements.txt`, no frontend, no compose. |
| 05 | `05_infra-orchestrator.md` | Compose tree driven by a Go CLI. |
| 06 | `06_embeddable-package.md` | The deliverable is a *published package* (UI component / SDK / headless engine) an external host mounts; `apps/web` is a reference host, not the product. |

If the user's shape doesn't cleanly match one, name the closest two and ask which they want — or document the hybrid explicitly.

### Step 4 — apply the cross-cutting conventions

For every layout, the same cross-cutting conventions apply (layout-specific adjustments documented per-layout). The **level charters** (`references/2-repo/00_charter.md`, `references/3-app/00_charter.md`, `references/4-feature/00_charter.md`) enumerate every decision area per level with its owning reference; the ownership map in `references/00_altitude-model.md` and the **file map** at the bottom of this document are the exhaustive index — walk the convention areas the project actually has and read the files whose comments match. Ordering hints:

- `references/2-repo/runtime/` — **start at `overview.md`**, the one map of how mise + `ctl` + docker + env interact; the other runtime files hang off it.
- `references/2-repo/ml-orchestration/` — start at `custom-orchestrator.md`.
- `references/3-app/frontend/` + `references/4-feature/` — any styling surface **must include `references/4-feature/styling-discipline.md`** (see ⚠️ above).
- Docs are a handoff, not our work — see `references/1-ecosystem/docs-placement.md` (the docs plugin is now `agent-ks`, scaffolded via `/agent-ks-init`).
- Versions in all references are illustrative — check latest stable and let the user pick.

### Step 5 — propose, then act

- For `/ps-setup` (init): present the proposed tree as text, list every file you'll create, then ask once before writing. Drop snippets from `assets/snippets/` where they fit. **Install the runtime layer by copying, never authoring**: `cp -r "${CLAUDE_PLUGIN_ROOT}/assets/snippets/scripts" ./scripts && mv ./scripts/ctl ./ctl && chmod +x ./ctl`, then adapt by deletion (conformance floor: `references/2-repo/runtime/script-overview.md`); generate `.gitignore` from `assets/snippets/env/gitignore.template`, keeping only the ecosystems present. **Always create the project `CLAUDE.md` from `assets/snippets/claude/CLAUDE.md.template`** — resolve the hard rules AND the structure-contract block (recorded variant choices, skeletons with this project's real names, tripwire numbers, escalation pointer), and include the styling-discipline block whenever the repo has a frontend. A bootstrap that skips any of its blocks has not delivered the conventions at all.
- For `/ps-setup audit`: produce a drift report. Read-only. Do not change files.
- For `/ps-setup suggest`: produce a proposal for the current repo. Don't change files; if the user wants to apply, they can re-run with init flow on top.

## Audit / suggest mode

When the mode is `audit` or `suggest`:

1. Read the current repo structure (top-level + `apps/*`, `packages/*`, `docker/`, `infra/`, `data/`, `scripts/`) **and the project CLAUDE.md** — its structure-contract block holds the recorded variant choices, which are the audit baseline. **A missing structure contract is itself a red finding**; without one, audit against the defaults and say so.
2. Identify the closest layout **and the recorded variants**. Compare the repo against its **recorded choices**, not just the canonical trees — a plane-grouped topology or a root-manifest exception with a recorded choice is conformant; the same shape unrecorded is drift.
3. Walk the levels (each charter ends with its audit list):
   - **L1** (`references/1-ecosystem/00_charter.md`): siblings/roles stated in CLAUDE.md when siblings exist; cross-repo sharing pinned; one docs home.
   - **L2** (`references/2-repo/00_charter.md`): root contract (loose code at root, runtime deps in a root manifest = T10, polyglot repo with a root-rooted workspace, missing/incomplete `.gitignore`, tracked `.env` = red); **`ctl` conformance floor** — `_lib.sh` sourced, `scripts/common/` present, verbs routed to workers; a single-file `ctl` with inlined bodies = **red**; compose axes (ports in base, profiles without a recorded escalation); env split; README three paths.
   - **L3** (`references/3-app/00_charter.md`): **count** feature folders per app (T2) and files per feature folder (T3) — crossings with no recorded deferral = findings; frontend skeleton presence (`pages/`, `api/` in a grown app); local `ui`/`styles` duplicating workspace packages = red; migration ownership (two backends sharing DDL, migrations-on-boot in a two-backend repo = red — `references/3-app/backend/two-plane-split.md`).
   - **L4** (`references/4-feature/00_charter.md`): the mechanical greps — server calls outside `api/`, and (when `tokens.css` + a ui package exist) the styling-discipline greps from `references/4-feature/styling-discipline.md`; file caps (T5); a missing styling block in CLAUDE.md = **red**, because nothing else holds the line for future agents.
4. For each convention area, list findings tagged by level:
   - **Matches** (green) — what's already aligned
   - **Drift** (yellow) — minor deviations
   - **Missing** (red) — conventions not present
5. For `audit`, stop there.
6. For `suggest`, follow with a proposed remediation plan — what to add, what to rename, what to split — and batch the moves into a consolidation window (`references/00_altitude-model.md` § evolution machinery) rather than dribbling renames across PRs.

Never edit files in `audit` mode. In `suggest` mode, only edit after explicit confirmation.

## When to ask vs assume

| Situation | Ask? |
|---|---|
| Repo cardinality (mono vs poly, # backends, # frontends) | Always ask if not stated; never infer from file presence alone. |
| Identity planes (operator/admin vs end-user) | Always ask when an admin surface exists — it drives backend count, the migrations owner, and exposure (`references/3-app/backend/two-plane-split.md`). |
| Grouping topology + workspace rooting (2+ apps) | Ask when more than one variant fits; record the pick in the project CLAUDE.md (`references/2-repo/grouping-topology.md`). |
| Language mix | Ask; don't assume from `*.py` extensions (might be ML, might be app). |
| ML vs app project | Ask explicitly. The Python flow differs. |
| Sibling-repo dependencies | Always ask. Cannot infer from inside one repo. |
| Theme / dark mode requirement | Ask if frontend exists. Default both modes; opt out for marketing pages. |
| Deployment targets (WSL / bare server / cloud / Traefik present) | Ask before generating prod compose. |
| Build-time vs runtime for each env var | Walk through each `.env.example` line with the user. |
| Existing `.env` content (when auditing) | Do not read `.env` files — they contain secrets. Read `.env.example` only. |
| Image / runtime versions (postgres:?, redis:?, python:?) | Always — versions in this skill's references are illustrative. Check latest stable, surface options, let the user pick. |
| ML cloud GPUs (none / `scripts/cloud/` wrappers / thin custom CLI) | Always ask for ML projects. |
| Remote dev / agent SSH access for ML projects | Always ask — different layout surface (`apps/cloud/`, `tasks/`, `scripts/cloud/`). |

**Running autonomously (no user available to ask)?** Don't guess silently and don't stall: take the convention default, proceed, and record every assumption explicitly in the proposal and the generated CLAUDE.md so the user can correct it later. An explicit wrong assumption is recoverable; a silent one becomes drift.

## What you do not do

- Do not generate a full project template. Use snippets.
- Do not assume a workspace tool (`pnpm-workspace.yaml`, `turbo.json`) when a single-frontend project doesn't need one.
- Do not force ML projects into the app shape — Layout 04.
- Do not edit anything without showing the plan first and getting confirmation.
- Do not read `.env` files (secrets); `.env.example` is the contract.
- Do not invent file paths from training data — consult `references/handoffs/examples-registry.md` to cite real examples.

## File map — everything in this skill, annotated

Read the file whose comment matches the decision in front of you. Paths are relative to this skill folder; snippet/command paths are relative to the plugin root. The tree IS the altitude model: folders are levels, each level opens with a `00_charter.md` (or `00_index.md`) routing to its topical owners.

```
references/
├── 00_altitude-model.md            # ★ THE SPINE — the 4 levels + binding times, routing rule, 5 principles, MASTER TRIPWIRE TABLE, OWNERSHIP MAP (axis→owner), evolution machinery
├── 01_question-flow.md             # level-ordered questions (L1→L2→L3; L4 never asked); ALWAYS-ask list
├── 02_decision-tree.md             # the L2 layout picker: answers → layout + grouping + config/env placement
│
├── 1-ecosystem/                    # L1: across repos — cardinality, boundaries, docs home, cross-repo contracts
│   ├── 00_charter.md               # L1 decision index → owners, invariants, interfaces, audit list
│   ├── repo-boundaries.md          # mono vs poly; own-repo criteria; deployed-vs-distributed; escalation between them
│   ├── docs-placement.md           # in-repo docs/ vs separate docs repo + handoff to the docs plugin (agent-ks, /agent-ks-init)
│   └── cross-repo-contracts.md     # aggregator repo, env.example sync, sharing ranking (publish>pin>vendor), image registry/semver, no-shared-tables
│
├── 2-repo/                         # L2: one repo — layout, topology, runtime triad, env, root contract, deployment, DB engines
│   ├── 00_charter.md               # L2 decision index → owners, invariants, variants list, audit list
│   ├── layouts/                    # pick ONE via the decision tree
│   │   ├── 01_single-app.md            # exactly one app — CLI/lib/lone backend or lone frontend
│   │   ├── 02_multi-app-monorepo.md    # 2+ apps; backend/frontend scaling spectrum, mesh end, core-vs-BFF axis (topology → grouping-topology.md)
│   │   ├── 03_polyrepo-aggregator.md   # the -deploy aggregator repo's SHAPE (when-polyrepo lives in 1-ecosystem)
│   │   ├── 04_ml-project.md            # ML repo shape (uvenv + requirements.txt, no compose)
│   │   ├── 05_infra-orchestrator.md    # compose tree driven by a Go CLI
│   │   └── 06_embeddable-package.md    # package + reference-host repo shape + publishing mechanics + single-artifact delivery
│   ├── grouping-topology.md        # ★ flat/plane-grouped/hybrid + workspace rooting (JS-only vs polyglot) + package placement scope — T1
│   ├── root-and-hygiene.md         # root-as-index, orchestration-only root manifest (T10), single-package containment + exceptions, .gitignore doctrine
│   ├── readme-three-paths.md       # root README contract + per-service READMEs (host dev loop)
│   ├── runtime/                    # the execution triad: mise + ctl + docker
│   │   ├── overview.md             # ★ START HERE: how mise + ctl + docker + env interact (the ONE map); others link here
│   │   ├── mise.md                 # .mise.toml version contract + bare-name PATH (versions illustrative)
│   │   ├── docker-overview.md      # docker/ layout + path discipline; standalone config (replaces base) vs compose.m.* modifiers + expose tiers
│   │   ├── docker-details.md       # bind-mounts + data/ layout + internal-vs-host ports + YAML anchors
│   │   ├── multi-stack.md          # two+ repos' stacks sharing one docker network: external networks, unique service names, cross-stack URLs
│   │   ├── script-overview.md      # the ctl/scripts model (common/ libs + dev|container|config workers) + conformance floor + the 2 custom bodies
│   │   ├── script-usage.md         # command surface + skeleton + interactive ctl up (plan/--list) + scripts/*.sh map + setup/status
│   │   ├── script-alternatives.md  # opting out of mise/docker/uv→uvenv·venv·poetry/bun→pnpm·npm: which .sh lines to edit
│   │   ├── no-data-core.md         # DATA_SVCS=() topology swap: apps-as-core for a DB-less project
│   │   └── complex-setups.md       # profiles as escalation + multi-mode docker/<mode>/ trees + escalate ctl → a Go binary (→ Layout 05); T7
│   ├── env-and-config/             # the env/config split
│   │   ├── env-precedence.md            # where a value comes from & who wins: 3 tiers + root .env scope + .env.example + config.local.yaml
│   │   ├── per-service-config.md        # each backend's config.yaml + ${VAR} interpolation from root .env
│   │   ├── frontend-env-isolation.md    # SECURITY: build-time vs runtime + VITE_*/NEXT_PUBLIC_* must not leak secrets to the bundle
│   │   └── secrets-matrix.md            # dev / CI / prod / Vault — where secrets live, rotation
│   ├── databases-provisioning.md   # engine choice (right floor) + infra/ (committed config) vs data/ (gitignored state) placement — ONE file (usage → 3-app)
│   ├── deployment/                 # exposure + production posture (repo-level)
│   │   ├── proxy-and-exposure.md   # the /api/* routing contract, Vite-proxy↔nginx pair, Traefik/expose posture
│   │   └── production-readiness.md # liveness/readiness, graceful shutdown, limits, migrations-on-deploy checklist (worker model → 3-app serving)
│   ├── platform/                   # non-web targets
│   │   ├── mobile.md               # native iOS (Swift) + Android (Kotlin) under apps/
│   │   └── desktop.md              # Tauri (default) / Electron; share packages/ with web
│   ├── ml-orchestration/           # cloud GPU training/inference (Layout 04)
│   │   ├── custom-orchestrator.md  # START HERE for ML cloud; scripts/cloud/ wrappers → thin CLI escalation
│   │   ├── spot-instances-and-checkpoints.md  # surviving spot preemption; checkpoint-resumable training
│   │   ├── inference-autoscaling.md    # batch vs online serving; autoscale + redeploy on preemption
│   │   ├── remote-dev-ssh-vscode.md    # one-command remote GPU box + SSH + VS Code Remote + Claude on box
│   │   ├── agent-ssh-access.md     # how an agent operates a remote box safely (perms, CLAUDE.md brief)
│   │   └── cicd-for-ml.md          # cheap/medium/expensive pipeline tiers for ML
│   └── tooling/                    # optional dev tooling + CI/CD
│       ├── lefthook.md             # pre-commit hooks (format/lint pre-commit, tests pre-push)
│       ├── vscode-debugger.md      # .vscode/launch.json etc. for the no-docker host path
│       └── ci-cd-future.md         # GitHub Actions templates; Vault-later notes (general app CI)
│
├── 3-app/                          # L3: one app or package — skeletons, domains, migrations, DB usage
│   ├── 00_charter.md               # L3 decision index, per-app questions, invariants, audit list
│   ├── backend/                    # backend-language flow (Python today)
│   │   ├── app-skeleton.md         # flat app/ rule (run-service vs src-layout), pyproject+uv flow, top-level skeleton (main.py, core/, feature folders)
│   │   ├── domain-grouping.md      # the domain layer: ownership-noun naming, aggregator routers, domain-shared placement, reconcile — T2 (internals → 4-feature)
│   │   ├── migrations.md           # ★ DECISION: Alembic default vs raw-SQL vs when-not-Alembic vs no-tool; entrypoint-migrates vs one-shot vs neutral owner
│   │   ├── alembic-recipe.md       # mechanics: init recipe, ini/env.py, daily flow, docker entrypoint
│   │   ├── raw-sql-recipe.md       # mechanics: 3-file pattern, shim, helpers, sqlx drift check
│   │   ├── two-plane-split.md      # admin/user split decision + apps/db neutral owner + one-DB ownership
│   │   ├── serving.md              # per-language worker model, recycling, timeouts
│   │   └── ml-python-flow.md       # requirements.txt + uvenv global env for ML
│   ├── frontend/                   # Vite/React + theming + workspaces + embeddable
│   │   ├── app-skeleton.md         # ★ THE answer to "structure of the frontend": app placement + config + hard src/ skeleton + layer import rules + workspace reconciliation + layout-shells (internals → 4-feature)
│   │   ├── workspaces-mechanics.md # mechanics: pnpm/turbo/bun config bodies, catalog, globalEnv, ctl shape (decisions → grouping-topology)
│   │   ├── shared-packages.md      # package internals: ui/styles/services/types, export surface, ~15-component grouping (T4), tailwind-config wiring
│   │   ├── tokens-setup.md         # tokens.css content/location, light-dark data-attr, shadcn wiring (USAGE discipline → 4-feature)
│   │   ├── framework-variants.md   # when Next (SSR) / Astro (static) instead of Vite
│   │   └── embeddable-seams.md     # embedding seams / IoC config API / per-instance mounts (repo shape + publishing → layout 06)
│   └── database-usage/             # per-engine usage conventions (engine choice → 2-repo/databases-provisioning.md)
│       ├── postgres.md             # compose block, init scripts, extensions (versions illustrative)
│       ├── redis.md                # AOF, requirepass, db numbers, Streams (versions illustrative)
│       ├── sqlite.md               # WAL + busy_timeout + single-writer model; the right floor
│       └── other-engines.md        # Mongo/Neo4j/Kuzu/Seaweed/Meili usage ("which to pick" table → 2-repo/databases-provisioning.md)
│
├── 4-feature/                      # L4: folders, files, content — delivered via CLAUDE.md blocks, never asked
│   ├── 00_charter.md               # L4 index, delivery mechanism (CLAUDE.md blocks), mechanical audit greps, hands-back-up rule
│   ├── feature-folders.md          # {router,service,repository,models}.py shape, feature seams, adapter-modules, backend subdivision (T3 backend)
│   ├── api-and-pages.md            # api/ internals (endpoints, zod, error norm, query keys, domain mirroring), thin pages (T6), URL mirroring, fetch grep, frontend subdivision (T3 frontend)
│   ├── types-and-contracts.md      # ALL type/DTO placement, both planes: models.py DTOs, no cross-domain imports, zod-inferred types, packages/types re-export
│   ├── styling-discipline.md       # ★ HARD RULES: primitive-first feature code, tokens only, stock vocabulary + allowlist, fold-on-second (T8) → into project CLAUDE.md
│   └── caps-and-extraction.md      # 500/300 caps (T5), rule of three (T9) / rule of two styling (T8 cite), folders-by-feature + kind-folder exceptions, test co-location
│
├── 5-examples/                     # complete ANONYMIZED annotated project trees; each ends with "which references govern each part"
│   ├── 00_index.md                 # what the examples are, how to read them, mapping example ↔ layout ↔ key variants
│   ├── 01_single-cli.md            # Layout 01: a distributable CLI tool (src-layout, minimal ctl, no compose)
│   ├── 02_canonical-1be-1fe.md     # Layout 02 flat: FastAPI + Vite, full runtime triad, tokens, alembic — the flagship example
│   ├── 03_two-plane-monorepo.md    # Layout 02 plane-grouped: apps/server/{api-platform,api-admin} + apps/db + apps/client/{platform,admin,packages/} rooted at client/
│   ├── 04_ml-training-project.md   # Layout 04: uvenv, configs/, scripts/cloud/, checkpoints
│   ├── 05_polyrepo-aggregator.md   # Layout 03: three service repos + the -deploy aggregator (env sync, image-based compose)
│   └── 06_embeddable-package.md    # Layout 06: packages/editor product + react-less core + reference host
│
└── handoffs/                       # peripheral / external-tool handoffs (docs handoff lives at 1-ecosystem/docs-placement.md)
    ├── claude-folder.md            # .claude/ stays empty initially; CLAUDE.md template guidance
    └── examples-registry.md        # the per-installation registry of the user's real repos to cite; never invent paths

assets/snippets/                    # fragments to drop into a target repo (NOT read as guidance)
├── frontend/{tokens,globals,light-dark}.css, vite-proxy.config.ts
├── docker/compose.yaml (profile-less base, whole stack) + compose.{data,prod}.yaml (standalone configs) + compose.m.{expose,expose_data,expose_all,traefik}.yaml (modifiers)
├── infra/nginx.conf
├── python/{alembic-shim.py, alembic_helpers.py}
├── env/{env.example.template, mise.toml.example, gitignore.template}
├── scripts/ctl (thin router → repo root) + common/{_lib.sh,_select.sh} + workers dev/* container/* config/*
├── claude/CLAUDE.md.template       # hard rules + structure-contract block + NON-NEGOTIABLE styling-discipline block — ALWAYS instantiated on bootstrap
└── README.md                       # snippet index: what each fragment is + where it drops

commands/ps-setup.md                # the /ps-setup slash command (init | audit | suggest)
```

## See also

- Spine: `references/00_altitude-model.md` (levels, principles, tripwires, ownership map).
- Snippets: `assets/snippets/` for fragments to drop in (see the snippet README for the index).
- Slash command: `commands/ps-setup.md` (the user-facing entrypoint).
- Examples cited: `references/handoffs/examples-registry.md`; annotated trees: `references/5-examples/`.
