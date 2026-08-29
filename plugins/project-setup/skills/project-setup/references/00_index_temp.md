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
| 1 | `01_layout.md` | The one tree. Placement rules. `.gitignore`. README levels. Naming. Exceptions. | synced to template |
| 2 | `02_env.md` | The five files. Rules. Loader steps. Docker consumption. Secret classes. | written |
| 3 | `03_setup.md` | Rules that hold in every case. The dev/prod pair. Cases 1–7: same server, different server, several frontends (dev proxy + one image), Next.js server, several backends, static only, multiple origins. | written |
| 4 | `04_stack.md` | Dev tools. Frontend kinds + theme + shared code. Backends. ML. Desktop, TUI, mobile. Data engines. Migrations decision. | written |
| 5 | `05_ctl.md` | Verb table. Compose model + merge rules. `ctl check` rules. Prod-readiness checklist. Frozen builds. Multi-stack. No data core. | written |
| 6 | `06_testing.md` | Placement. Verbs. Rules. Linters. | written |
| 7 | `07_conventions.md` | Agent brief. Inside an app. Naming. Residue. Tripwires. Audit order. | written |

Questions to ask before scaffolding go into `SKILL.md`, not a page. Deleted: `02_environment`, `03_stack`, `04_testing`, `06_frontend`, `07_backend`, `08_conventions`, `09_questions`.

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
- [x] `compose.m.expose_web.yaml`, `m.expose.yaml`, `m.env_override.yaml`. Traefik dropped: any host proxy sits outside this repo.
- [x] all paths root-relative, no `../`
- [ ] prod readiness in base: `x-defaults` anchor (`restart`, logging, `stop_grace_period`), `deploy.resources` per service, app healthchecks with `start_period`
- [ ] decide: migrate as one-shot compose service gate, or `up.sh` runs migrate (current). Pick one, delete the other.
- [ ] `<version>` on every image

### apps/ — backend
- [x] `example-api-python/` FastAPI: `app/{main,config,routers,services,models,schemas,db}`, `config.yaml`, `Dockerfile`, `pyproject.toml`, `README.md`
- [x] `example-engine-rust/` Axum: `src/{main,config,routes,db}`, `config.yaml`, `Dockerfile`, `Cargo.toml`, `README.md`
- [ ] `/health` and `/ready` routes named in `main.py` / `routes/mod.rs`
- [ ] rate limit + `X-Forwarded-*` handling named in `main.py`
- [ ] AI key proxy route named in `routers/` (backend-only rule)

### apps/ — frontend
- [x] `example-multi-web-app/` group: `Dockerfile` (one image, ends in nginx), `README.md`, `app/` Vite SPA `/app`, `landing/` Next export `/`, `docs/` Astro `/docs`
- [x] `example-single-web-app-vite/` — one SPA, own Dockerfile + `nginx.conf.template`, vite proxy, `e2e/`
- [x] `example-dashboard-nextjs/` Next.js SSR `/dashboard`, own Dockerfile and service
- [x] `infra/nginx/{prod,dev}.conf.template`, envsubst, prefixes and ports from root `.env`
- [x] `docker/compose.dev.yaml` dev proxy on host network; `ctl dev --proxy`
- [x] `compose.m.expose_web`; no separate nginx service
- [x] `apps/.dockerignore` for the `./apps` build context
- [x] api → engine via `ENGINE_URL` (`config.yaml` `${VAR}`, compose literal, env_override)
- [x] `packages/styles/` — `tokens.css`, `globals.css`, `elements.css` from vault
- [x] `packages/ui/` — shadcn shape, React as peerDependency
- [x] `packages/types/` — API contract, generated
- [x] `packages/tsconfig/` — shared base
- [x] `e2e/` folder (in the single SPA)
- [ ] one colocated `*.test.tsx` example
- [ ] PWA note: manifest in `web/public/`, not an app

### apps/ — other
- [x] `example-tui-go/` Go: cobra + bubbletea, keyring token
- [x] `database/{postgres,neo4j,redis}/` — hand-written migrations, advanced indexes in `0002`
- [x] `infra/nginx/` (prod edge template), `infra/nginx-dev/` (host-network dev proxy template)
- [-] `notebooks/` — absent, folder exists only when used. Layout page says so.
- [-] desktop (`tauri/`) and mobile — not in template. Architecture page covers in one table row each, pointing at vault's `apps/client/tauri` shape.

### Cross-cutting
- [ ] `ctl check` covers: config.yaml keys ⊆ `.env.example`, no manifests at root/apps, no ports in base, no `../` in compose, compose config valid per combination, `CLAUDE.md` content. TODO: `.env.example` comment rule.
- [ ] every `<version>` placeholder present, none filled
- [ ] one smoke run of `ctl check`, `ctl up --dry-run`, `ctl dev --dry-run` on a copy with docker

## Decisions taken — must appear in the named page

| Decision | Page |
|---|---|
| Single origin, always. The browser talks to one host. Vite proxy routes `/api` in dev; nginx in prod; a Next.js server proxies for itself. Multi-origin only for a public SDK. | 4, 5 |
| Static frontends live under `apps/web/<name>/` and build into ONE image that ends in nginx: that image is the `web` service and the edge. A server frontend (Next.js SSR) is its own app and service. Several frontends in dev share an origin through `compose.dev.yaml`. | 5 |
| The frontend bundle carries no environment value. `apps/<fe>/.env` holds build constants only (`VITE_BASE_PATH`, display name). Proxy targets come from the root `.env` via the process env. No `config.jsonc`. | 2, 4 |
| Backend precedence: process env > `config.local.yaml` (gitignored, literals only) > `config.yaml` (committed, `${VAR}` for secrets and endpoints). One loader per backend, finds the repo root, loads root `.env` skip-if-set. | 2 |
| Backend hosts and ports: single server — root `.env` for `ctl dev`, literals in `compose.base.yaml` for docker. Multi-server — `+env_override` re-points a service to `${VAR}` from root `.env`; a piece not in this compose is reached by its `.env` value. | 2, 3 |
| Compose and ctl read only the root `.env`. `ctl build` forwards `apps/<fe>/.env` opaquely as build args. | 2, 3 |
| Base is prod. `compose.db.yaml` included by base; loopback ports on engines; no ports in base; modifiers add exposure. Paths root-relative via `--project-directory`. | 3 |

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
