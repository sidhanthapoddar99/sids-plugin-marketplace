---
name: project-setup
description: Use when bootstrapping a new project, auditing an existing one for layout conventions, or proposing an ideal structure for a half-done repo. Covers mono- and poly-repo apps, single and multi backend/frontend, ML projects, and infra-orchestrator topologies. Triggers on "init a project", "setup a new repo", "scaffold a monorepo", "what should this repo look like", "audit my layout", "structure this project", "where should config.yaml live", "how should I split docker-compose", "single .env or per-service", "multi-frontend monorepo", "design tokens setup", anything around `./dev` wrapper conventions, mise, design tokens, the `apps/`, `packages/`, `infra/`, `data/`, `docker/` folder split, secrets matrix, modularity rules.
---

# project-setup

You are inside Sid's `project-setup` plugin. Your job is to help the user lay out, configure, or audit a project according to Sid's conventions — without inventing fresh patterns each time.

## Hard rules

1. **No single ideal structure exists.** The right layout depends on shape questions. Always consult the question flow before proposing anything.
2. **If you don't have information, ASK.** Do not presume. Common unknowns: sibling repos, whether the project is ML or app, whether the frontend exposes any backend URLs, deployment targets, theming requirements.
3. **No `src/` at repo root.** Always nest inside `apps/<name>/src/` (or `packages/<name>/src/`) so there is room to grow without restructuring.
4. **Per-service `config.yaml`, root `.env`.** Root `.env` holds shared/common vars only. Each backend owns its own `config.yaml`. Frontends have their own env scope (`VITE_*` / `NEXT_PUBLIC_*`) — backend secrets must never leak there.
5. **Compose lives in `docker/`** by default, with files representing deployment modes (base / database-only / dev / prod / traefik / no-ports). Bind-mounts only.
6. **One `./dev` wrapper at repo root.** Setup folds in. No separate `setup.dev.sh`. Subscripts in `scripts/` are implementation, the wrapper is the public API.
7. **README documents three startup paths** — wrapper script, raw docker compose, no-docker host run.
8. **Examples are evidence, not gospel.** They evolved at different times. Cite them, do not blindly copy.

## Workflow

When the user asks anything in scope, walk this flow:

### Step 1 — read the decision tree

Open `references/00_decision-tree.md`. It maps question answers → topology + key decisions.

### Step 2 — run the question flow

Open `references/01_question-flow.md`. Run through it in order. Ask the user only the questions whose answer you can't reliably infer from the current repo or conversation. Skip what's already answered. Stop and confirm if any answer is ambiguous.

### Step 3 — pick a topology

Based on the answers, pick a topology from `references/topologies/`:

| # | File | When |
|---|---|---|
| 01 | `01_single-app.md` | A single CLI / library / tool. No frontend, no microservices. |
| 02 | `02_monorepo-1be-1fe.md` | Single backend + single frontend. The common case. |
| 03 | `03_monorepo-multi-backend.md` | Multiple backends in different languages coordinating via Redis/DB. |
| 04 | `04_monorepo-multi-frontend.md` | Multiple frontends sharing a `packages/ui`. |
| 05 | `05_monorepo-microservices-mesh.md` | Many small backends with their own service boundaries. |
| 06 | `06_polyrepo-with-aggregator.md` | Each service in its own repo + a `-deploy` aggregator repo. |
| 07 | `07_ml-project.md` | uvenv global env, `requirements.txt`, no frontend, no compose. |
| 08 | `08_infra-orchestrator.md` | Compose tree driven by a Go CLI. |

If the user's shape doesn't cleanly match one, name the closest two and ask which they want — or document the hybrid explicitly.

### Step 4 — apply the cross-cutting conventions

For every topology, the same conventions apply (with topology-specific adjustments documented per-topology). Consult:

- `references/env-and-config/` — root `.env`, per-service `config.yaml`, frontend env isolation, build-time vs runtime, `${VAR}` interpolation, secrets matrix
- `references/docker-compose/` — `docker/` folder layout, deployment modes, bind-mounts, nested-data-dir trick, escalation to Go CLI
- `references/scripts/` — `./dev` wrapper pattern, subscripts, dev-without-docker, three startup paths, setup folded in
- `references/python/` — `uv` for apps, `uvenv` for ML, Alembic conventions
- `references/frontend/` — Vite/proxy/nginx pair, multi-frontend workspaces, design tokens, light/dark
- `references/databases/` — `infra/` vs `data/`, postgres/redis/seaweed/mongo/neo4j conventions
- `references/modularity/` — 500/300 line caps, folders by feature, extract on third use
- `references/mise.md` — version pinning contract
- `references/claude-folder.md` — `.claude/` conventions (empty by default)
- `references/readme-three-paths.md` — README contract
- `references/docs-integration.md` — hand off to `/docs-init` for docs
- `references/ci-cd-future.md` — placeholder, GitHub Actions / Vault notes
- `references/examples-index.md` — pointers to the real-world examples (atheneum, NeuraSutra, plane, chimere)

### Step 5 — propose, then act

- For `/ps-setup` (init): present the proposed tree as text, list every file you'll create, then ask once before writing. Drop snippets from `assets/snippets/` where they fit.
- For `/ps-setup audit`: produce a drift report. Read-only. Do not change files.
- For `/ps-setup suggest`: produce a proposal for the current repo. Don't change files; if the user wants to apply, they can re-run with init flow on top.

## Audit / suggest mode

When the mode is `audit` or `suggest`:

1. Read the current repo structure (top-level + `apps/*`, `packages/*`, `docker/`, `infra/`, `data/`, `scripts/`).
2. Identify the closest topology.
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

## What you do not do

- Do not generate a full project template. Use snippets.
- Do not assume a workspace tool (`pnpm-workspace.yaml`, `turbo.json`) when a single-frontend project doesn't need one.
- Do not force ML projects into the app shape — Topology 07.
- Do not edit anything without showing the plan first and getting confirmation.
- Do not read `.env` files (secrets); `.env.example` is the contract.
- Do not invent file paths from training data — consult `references/examples-index.md` to cite real examples.

## See also

- Spec: `summary.md` at the plugin root.
- Snippets: `assets/snippets/` for fragments to drop in.
- Slash command: `commands/ps-setup.md` (the user-facing entrypoint).
