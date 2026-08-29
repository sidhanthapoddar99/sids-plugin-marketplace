# Rewrite index — TEMPORARY. Delete before tagging.

Working map for the rewrite. Tracks what each page must cover, where the template carries it, and what is done.
Legend: `[x]` done · `[ ]` open · `[-]` dropped on purpose.

## Plan

1. Finish this checklist.
2. Finish the template. Freeze paths.
3. Write pages one at a time. Audit each against the checklist.
4. Write `SKILL.md`. Delete `references_old/`, `snippets_old/`, this file. Tag `project-setup/v1`.

## Pages

| # | File | Owns | Status |
|---|---|---|---|
| 1 | `01_layout.md` | The one tree. Placement rules. `.gitignore`. README levels. Naming. Exceptions. | written, needs template sync |
| 2 | `02_environment.md` | `.env` / `.env.example` / `config.yaml`. Value flow. Secret classes. Docker consumption. | written, needs path sync |
| 3 | `05_ctl.md` | Compose model (db / base / m.*). `ctl` verbs. Prod readiness. Multi-stack. | empty |
| 4 | `03_architecture.md` | Stack tables. Why/when/never for frontend, backend, data, desktop, mobile, AI, security. | `03_stack.md` written; rename + extend |
| 5 | `04_testing.md` | Test placement. `ctl test`, `e2e`, `lint`, `gate`. Frozen builds. | empty |
| 6 | `08_conventions.md` | AGENTS.md / memory. Feature folders. Styling discipline. Caps. Residue. | residue only |
| 7 | `09_questions.md` | What to ask before scaffolding. Altitude in one paragraph. | empty |

Delete: `06_frontend.md`, `07_backend.md` (merged into 4). Renumber at the end so files read 01–07.

## Template checklist

### Root
- [x] `ctl` + `scripts/` real code (22 files)
- [x] `.env.example` full contract, grouped by consumer
- [x] `.mise.toml`, `.gitignore`, `.dockerignore`, `lefthook.yml`
- [x] `AGENTS.md`, `CLAUDE.md` = `@AGENTS.md`, `README.md`, `LICENSE`
- [x] `data/.gitignore` (`*` / `!.gitignore`)
- [x] `memory/00_rules.md`
- [ ] `README.md` layout block matches the final tree

### docker/
- [x] `compose.db.yaml` — engines, loopback ports, bind mounts
- [x] `compose.base.yaml` — is prod, no ports, no `env_file`, `include:` db, explicit `environment:` per service
- [x] `compose.m.expose_nginx.yaml`, `m.expose.yaml`, `m.env_override.yaml`, `m.traefik.yaml`
- [x] all paths root-relative, no `../`
- [ ] prod readiness in base: `x-defaults` anchor (`restart`, logging, `stop_grace_period`), `deploy.resources` per service, app healthchecks with `start_period`
- [ ] decide: migrate as one-shot compose service gate, or `up.sh` runs migrate (current). Pick one, delete the other.
- [ ] `<version>` on every image

### apps/ — backend
- [x] `api/` FastAPI: `app/{main,config,routers,services,models,schemas,db}`, `config.yaml`, `Dockerfile`, `pyproject.toml`, `README.md`
- [x] `engine/` Axum: `src/{main,config,routes,db}`, `config.yaml`, `Dockerfile`, `Cargo.toml`, `README.md`
- [ ] `/health` and `/ready` routes named in `main.py` / `routes/mod.rs`
- [ ] rate limit + `X-Forwarded-*` handling named in `main.py`
- [ ] AI key proxy route named in `routers/` (backend-only rule)

### apps/ — frontend
- [x] `web/` Vite: `src/{main,routes,components,lib/api}`, `vite.config.ts` proxy mirrors nginx, `.env.example`, `Dockerfile`
- [x] `site/` Next.js: `src/app/{layout,page}`, `next.config.ts` rewrites, `.env.example`, `Dockerfile`
- [x] `packages/styles/` — `tokens.css`, `globals.css`, `elements.css` from vault
- [x] `packages/ui/` — shadcn shape, React as peerDependency
- [x] `packages/types/` — API contract, generated
- [x] `packages/tsconfig/` — shared base
- [ ] `web/e2e/` folder + one colocated `*.test.tsx` example
- [ ] PWA note: manifest in `web/public/`, not an app

### apps/ — other
- [x] `cli/` Go: cobra + bubbletea, keyring token
- [x] `database/{postgres,neo4j,redis}/` — hand-written migrations, advanced indexes in `0002`
- [x] `infra/{nginx,traefik}/`
- [-] `notebooks/` — absent, folder exists only when used. Layout page says so.
- [-] desktop (`tauri/`) and mobile — not in template. Architecture page covers in one table row each, pointing at vault's `apps/client/tauri` shape.

### Cross-cutting
- [ ] `ctl check` covers: config.yaml keys ⊆ `.env.example`, no manifests at root/apps, no ports in base, no `../` in compose, compose config valid per combination, `CLAUDE.md` content. TODO: `.env.example` comment rule.
- [ ] every `<version>` placeholder present, none filled
- [ ] one smoke run of `ctl check`, `ctl up --dry-run`, `ctl dev --dry-run` on a copy with docker

## Old content map

Where each old area lands. Unlisted old files are dropped.

| Old | New | Carry |
|---|---|---|
| `00_altitude-model`, `01_question-flow`, `02_decision-tree` | 7 | altitude as one paragraph; the questions |
| `1-ecosystem/*` | 1, 7 | repo boundary and docs placement as two bullets |
| `2-repo/01-layouts/*` | 1 | one tree; exceptions list |
| `2-repo/02-root-hygiene/*` | 1, 6 | done |
| `2-repo/03-env-config/*` | 2 | done |
| `2-repo/04-docker/*` | 3 | merge rules, prod readiness, multi-stack paragraph, pre-deploy checklist |
| `2-repo/05-ctl-scripts-tooling/*` | 3 | verb table from `ctl --help`; lefthook one row. Drop vscode-debugger, ci-cd |
| `2-repo/06-runtime-environment/*` | 4 | mise row, done |
| `2-repo/07-ml-orchestration/*` | — | out of scope. Own skill if needed |
| `3-app/01-structure-and-stack/*` | 4 | stack tables, done; workspaces → `link:` rule |
| `3-app/02-backend/*` | 4 | core vs BFF, two-plane, one backend per responsibility |
| `3-app/03-web-app/*` | 4 | Vite vs Next, PWA row |
| `3-app/04-database/*` | 4 | engines table, migrations decision, done |
| `3-app/05-package/*` | 4, 6 | `link:` + peerDeps + exports; tokens → template |
| `3-app/06-desktop`, `07-mobile` | 4 | one row each |
| `3-app/08-ai/*` | 4 | keys backend-only; MCP server = a backend app |
| `3-app/09-security-hardening/*` | 4 | edge protection, rate limit, telemetry as one table |
| `3-app/10-deployment/*` | 3 | worker model one paragraph; packaging → template Dockerfiles |
| `4-feature/*` | 6 | feature folders, styling discipline, caps and extraction, types contract |
| `5-examples/*` | — | the template is the example |
| `handoffs/*` | — | obsolete |
