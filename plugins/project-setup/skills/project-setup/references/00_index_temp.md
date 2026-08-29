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
| 01 | `01_layout.md` | The one tree. Placement rules. One repo or two. Ignore files. README levels. Naming. Exceptions. | reviewed |
| 02 | `02_env.md` | Three env files + templates, `config.yaml`, `config.local.yaml`. Rules. Loader steps. Docker consumption. Secret classes. | reviewed |
| 03 | `03_routing.md` | Single origin. The dev/prod pair. Cases 1–7. nginx rules that bite. | reviewed (renamed) |
| 04 | `04_stack.md` | The choice only: dev tools, frontend kinds + language rules, backend languages, data engines, ML, desktop/mobile. | split 2026-08-30 |
| 05 | `05_frontend.md` | Theme + switching, typography policy, `frontend-design` precedence, folder shape + import matrix, api layer, feature rules + greps, PWA, published package. | new |
| 06 | `06_backend.md` | Every backend has, layout by size, domain slices + naming, serving per language, migrations (+ native tool, raw-SQL trio, sqlx order), engine gotchas, manager.py pointer. | new |
| 07 | `07_security.md` | The floor table (edge, tiers, captcha, rate-limit contract, tokens, operator identity, audit, telemetry, secrets, deps), AI keys, prompt injection, tripwires. | new |
| 08 | `08_ctl.md` | Verbs. Compose model. `ctl check`. `ctl manage`. Without data core / without ctl / escalation / ctl-shape check. | trimmed (renamed) |
| 09 | `09_production.md` | Base settings (x-defaults, restart, healthcheck, grace, limits, logging), health two questions, the deploy + migration run model, host rules (chmod 600, UID, TLS), sick-stack tells, frozen builds, observability, multi-stack, checklist. | new |
| 10 | `10_testing.md` | Kinds, ladder, rung contract, placement, conformance, rules, linters, verbs. | reviewed (renamed) |
| 11 | `11_conventions.md` | The brief contract (sections), scope and decoupling, caps + rule of three/two, naming, residue, tripwires, audit order. | rewritten |

Questions to ask before scaffolding, the always-ask list and the 5–10 bullet confirmation go into `SKILL.md`, not a page. Deleted: `02_environment`, `03_stack`, `04_testing`, `06_frontend`, `07_backend`, `08_conventions`, `09_questions`.

## Template checklist

### Root
- [x] `ctl` + `scripts/` real code (22 files)
- [x] `.env.secrets.template`, `.env.data.template`, `.env.proxy.template` with headers and per-key comments
- [x] `.mise.toml`, `.gitignore`, `.dockerignore`, `lefthook.yml`
- [x] `AGENTS.md`, `CLAUDE.md` = `@AGENTS.md`, `README.md`, `LICENSE`
- [x] `data/.gitignore` (`*` / `!.gitignore`)
- [x] `memory/00_rules.md`
- [ ] `README.md` layout block matches the final tree
- [x] `AGENTS.md` rebuilt as the brief contract (recorded choices, skeletons, tripwires, styling, exceptions, stack, commands, escalation); `memory/README.md` index; `memory/rules.md`

### docker/
- [x] `compose.db.yaml` — engines, loopback ports, bind mounts
- [x] `compose.base.yaml` — is prod, no ports, no `env_file`, `include:` db, explicit `environment:` per service
- [x] `compose.m.expose_web.yaml`, `m.expose.yaml`, `m.env_override.yaml`. Traefik dropped: any host proxy sits outside this repo.
- [x] all paths root-relative, no `../`
- [ ] prod readiness in base: `x-defaults` anchor (`restart`, logging, `stop_grace_period`), `deploy.resources` per service, app healthchecks with `start_period`
- [ ] decide: migrate as one-shot compose service gate, or `up.sh` runs migrate (current). Pick one, delete the other.
- [ ] `<version>` on every image

### apps/ — backend
- [x] `example-api-python/` FastAPI: `app/{main,config,db,core/,health/,<domain>/{models,repository,service,router}}`, `config.yaml`, `Dockerfile`, `pyproject.toml`, `README.md`
- [x] `example-engine-rust/` Axum: cargo workspace `crates/{common,data,auth,api}`, `rust-toolchain.toml`, `config.yaml`, `Dockerfile`, `Cargo.toml`, `README.md`
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
- [x] `packages/ui/` — theme (`src/styles/`) and components (`src/components/`) in one package; single SPA keeps the same shape in-app
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
- [x] `scripts/gate/`: ladder `lint typecheck dead audit test check build e2e`, one file per rung, `_gate.sh` (quiet re-exec, reject args, require target), `_lock.sh` (one run + memory lid); by-name `clones fuzz perf`. `ctl typecheck` worker added. `scripts/test/gate.sh` deleted.
- [x] `ctl up --services a,b` + interactive service picker after modifiers; `ctl dev` picks apps in a TTY (`--nqa` skips).
- [x] `require_docker` names the fault (missing · stopped · no-compose); runs before the first compose call in `up`, passthroughs, `build`. Bug fixed: dead engine reported as "invalid combination".
- [x] `ctl manage` break-glass console: `scripts/admin/manage.sh` + `apps/example-api-python/manager.py` stub; 05 section, 04 security-floor row.
- [x] Conformance example: `apps/example-api-python/tests/conformance/test_structure.py` (registry, two checks, red fixtures, ledger).
- [ ] Smoke-run the gate family on a real copy: `bash -n` passes; the rungs have not been executed against installed tools.
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
| Three root env files by role: `.env.secrets`, `.env.data`, `.env.proxy`, each from a committed `.template`. Compose and ctl read only these (`--env-file` ×3). No frontend env file; prefixes reach frontends from `.env.proxy` as build args / process env. | 2, 3 |
| Base is prod. `compose.db.yaml` included by base; loopback ports on engines; no ports in base; modifiers add exposure. Paths root-relative via `--project-directory`. | 3 |

## Parked from the 01–03 review — apply when writing these pages

| Page | Item |
|---|---|
| 05_ctl | `migrate → sqlx prepare --check → build` ordering for Rust + SQL |
| 05_ctl | Escalate to a compiled orchestrator only for structured state across runs |
| 05_ctl | Raw `docker compose` must keep working beside ctl (state the invariant) |
| 05_ctl | Prod env files `chmod 600`, owned by the app user |
| 05_ctl | Crash-loop tell: perpetually young `Up N seconds`, `RestartCount`, `grep emerg` |
| 07_conventions | `memory/` naming: flat kebab-case files + `README.md` index; `AGENTS.md` imports them with `@memory/<file>.md` |
| 07_conventions | Multi-repo naming `<product>-<role>`, prefix chosen at the first split |
| 07_conventions | Frozen legacy package kept beside its replacement: excluded from lint and gates, README first line says frozen |

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

## Gap check — old references vs the new pages (2026-08-30). Applied in the 11-page split except where marked open.

Still open in the TEMPLATE (pages now describe them): `compose.base.yaml` prod settings + redis/neo4j healthchecks; `gunicorn.conf.py` + Dockerfile CMD in `example-api-python`; `index.html` + `lib/theme.ts` + status tokens in the SPA and `packages/ui`; `alembic_helpers.py` + one `.up.sql/.down.sql` pair in `apps/database/postgres`; `lefthook install` in `setup.sh`; `.gitignore` tool caches; a ctl-shape rule in `check.sh`; `ctl manage` row in the vault-style `manager.py` is done.

Method: every file under `references_old/` and `snippets_old/` walked; each item grepped against `references/01–07` and `template/` before listing. Skipped: items already covered, and the dropped-by-decision topics (Traefik, process-compose, `infra/`, per-frontend `.env`, single root `.env`, `config.jsonc`, compose profiles, ML orchestration, vscode debugger, CI/CD, `handoffs/`, `5-examples`).

### Highest value (agent's ranking)

1. **Agent-brief contract** — `template/AGENTS.md` is 12 lines; pages 4/6/7 say "record it in AGENTS.md" (stack additions, gate rungs, exceptions, recorded choices, tripwire numbers, styling block) with no section to receive it.
2. **Production serving** — per-language concurrency (Python = gunicorn workers + recycling with jitter, graceful timeouts; Rust/Go/Node = one process, scale by replicas), workers matched to the CPU limit, never `uvicorn --reload` in a prod CMD. Page 03 promised "worker model one paragraph"; none exists.
3. **Typography allowlist + `frontend-design` precedence** — `text-sm` ~90 %, one emphasis weight, hierarchy by size+colour never weight; with tokens + a ui package this discipline overrides the `frontend-design` skill. Entirely absent from 04.
4. **AI posture** — prompt-injection rules (allowlist tools, validate args, never execute model output, tools through the service layer's authz), per-environment provider keys + spend caps, provider adapters, versioned prompt files, model IDs in `config.yaml`. Absent from 04.
5. **Theme switching** — nothing sets `[data-theme]`: localStorage + `prefers-color-scheme` writer, blocking pre-paint script for Next.js; the Vite SPA has no `index.html`. Status tokens (`--success/--warning/--danger/--info`) and a z-index scale missing from `tokens.css`.
6. **Raw-SQL migration mechanics** — 04 prescribes the Alembic shim; template ships no `alembic_helpers.run_sql` nor `.up.sql/.down.sql` pair. Contradiction: old rule "when Python is not the schema owner use `sqlx migrate` / `golang-migrate`", new forces Alembic. Plus parked `migrate → sqlx prepare --check → build`.
7. **Prod compose instance** — `compose.base.yaml` has no `x-defaults`, `restart`, app healthchecks with `start_period`, `stop_grace_period`, `deploy.resources`; `compose.db.yaml` has healthchecks for postgres only (so `wait_healthy` cannot judge redis/neo4j). Migrations as a one-shot compose service gated by `service_completed_successfully` still undecided.
8. **Domain naming** — domains are ownership nouns, never activities (`build/`, `sync/`) or UI nav labels; one aggregator router per domain; domain-shared helpers at the domain root not `core/`; two backends never share an ORM package (schema is the only contract).
9. **Engine gotchas** — SQLite pragmas (`WAL`, `busy_timeout`, `foreign_keys=ON`) + Alembic `render_as_batch=True`; Redis Streams need `maxmemory-policy noeviction`, AOF `everysec`, db-number map; Postgres `POSTGRES_INITDB_ARGS` locale, extension table (only `pgvector` survives).
10. **`ctl manage` — break-glass operator console (Sid: take).** Model: neura-cloud-vault `scripts/admin/manage.sh` → `apps/api-admin/manager.py`. Thin forward (`cd <admin backend> && uv run python manager.py "$@"`); `manager.py` at the backend root, argparse: `ops create|list|disable|enable|reset-password|lockout [--clear]`, `settings list|get|set <key> <json>`. Direct DB/redis through the app's own config loader and `hash_password`; every mutation written to `operator_audit`; operators disabled never deleted; needs the data core up. Rule: runs without the web auth flow, host access is the boundary; the only path that seeds the first SuperAdmin. Goes to 05 (verb table + a "Break-glass" section) and 04 (security floor row); template gets `scripts/admin/manage.sh` + `apps/example-api-python/manager.py` stub.
11. **Parked page-05 items still unwritten** — prod env files `chmod 600`; crash-loop tell (`Up N seconds`, `RestartCount`, `grep emerg`); escalate `ctl` to a binary only for structured state across runs; "raw `docker compose -f` must keep working beside ctl"; ctl conformance floor as a `ctl check` rule (`_lib.sh` sourced, every verb `run`-routed, single-file ctl = red).

### Full list, by old folder

| Old file | Item | Goes to | Verdict |
|---|---|---|---|
| `00_altitude-model` | Numbered tripwires with thresholds; crossing one obligates restructure **or a recorded deferral** | 07 | missing |
| `00_altitude-model` | Audits compare the repo against its recorded choices, not the canon | 07, AGENTS.md | partial |
| `00_altitude-model` | Evolution timing: reconcile in the milestone the domain settles; batch moves; audit triggers | 07 | missing |
| `00_altitude-model` | No written rule → resolve from principles and record it, never improvise inline | 07 | missing |
| `00_altitude-model` | The four altitudes (ties go up) | 07 | dropped; index promised "one paragraph" |
| `01_question-flow` | Always-ask list; 5–10 bullet confirmation before proposing | SKILL.md | pending SKILL.md |
| `01_question-flow` | Named defaults: zustand (client state), TanStack Query (server state); theming both modes, light-only marketing; OSS vs private | 04 | missing |
| `02_decision-tree` | Three placement categories (app / internal lib / published package); escalation table; never a root `config.yaml` | 01, 02 | partial |
| `1-ecosystem/repo-boundaries` | `<product>-<role>` naming (parked); each repo names its role and siblings in the brief; "aspirational independence" warning | 07, 01 | missing |
| `1-ecosystem/cross-repo-contracts` | One ecosystem hub with the repo map; image tag contract (`:sha` + `:tag`, never repurposed) | 01, 05 | missing |
| `1-ecosystem/docs-placement` | "None" is a valid docs answer; docs slot shape, vendored framework read-only; README docs pointer | 01, README | missing/partial |
| `2-repo/01-layouts` | Single app at top level (now reversed on purpose); per-service DB env namespacing; `ctl publish` verb; non-product signal in the build config | 01, 02, 05, 04 | contradicted/partial |
| `2-repo/02-root-hygiene` | Tool caches in `.gitignore` (`.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `coverage/`); README stack/commands/config tables; per-app env-var table | template | missing/partial |
| `2-repo/03-env-config` | `config.<env>.yaml` middle layer (dropped, not stated); `${VAR:-default}` / `${VAR:?}` forms (new says unset always fails — silent drop); per-service `__` prefix rationale; build-vs-runtime per-variable walk; secrets-manager graduation path | 02, 05 | contradicted/partial |
| `2-repo/04-docker` | `x-` anchors; bind-mount UID/SELinux `:Z`/never 777; `${DATA_DIR}` override cases; DB-less repo guard softening; security headers (HSTS, nosniff) + brotli; observability staging; readiness ⇒ pull from LB vs liveness ⇒ restart | 05, 03, 04 | missing/partial |
| `2-repo/05-ctl` | `ctl manage` break-glass operator console; setup never mutates config mid-launch; why apps run on the host in dev + never bind-mount source into a dev container; tool opt-out matrix (`02_script-alternatives` whole file); `lefthook install` wired in `ctl setup`; guard hook refusing commits under `data/` | 05, template | missing |
| `2-repo/06-runtime` | mise plus a second version manager = anti-pattern | 04 | missing |
| `3-app/01-structure` | App-vs-package test stated; no symlinks between apps; no repo scripts inside an app | 01 | missing |
| `3-app/02-backend` | `[tool.uv] package = false`, pytest `pythonpath`; `uv` hygiene (no `uv pip install`, no `requirements.txt`, never hand-edit lock); operator identity never via public signup, first admin by break-glass CLI; admin look ≠ reason to split | 04, 07, 03 | missing/partial |
| `3-app/03-web-app` | `index.html` + `data-theme`; `layout/` shells; `stores/` layer; layer import matrix (`lib/` never React/IO); ban on `context/`, `helpers/`, `types.ts` catch-alls; PWA installability checklist + SW update flow | template, 07, 04 | missing/partial |
| `3-app/04-database` | In-process cache vs Redis by worker count; SQLite→Postgres trigger; `create_all()` in prod = red; native migration tool per schema owner; SQLite pragmas; Postgres locale/extensions; Redis streams/AOF/db map; redis+neo4j healthchecks | 04, 07, template | missing/contradicted |
| `3-app/05-package` | ~15 flat components → group by family; no mega `packages/shared`; one export surface, no deep `src/` imports; theme toggle + pre-paint script; status tokens + z-index; never remap stock scale names; a token for a one-off = named magic number; seam `config` interface | 04, template | missing/partial |
| `3-app/08-ai` | `.mcp.json` committed, `${VAR}` secrets; stdio vs remote transport; tool surface versioned, pin third-party servers, thin adapter over `service.py`; provider adapters; prompts as versioned files; injection posture; per-env keys + spend caps | 01, 04 | missing |
| `3-app/09-security` | Three protection tiers recorded; `CF-Connecting-IP` behind a WAF; 429 + `Retry-After`; limits keyed on user/API key never raw IP for authed routes, per-class tiers; telemetry adapter with opt-out at the boundary; audit events ≠ request logs, retention policy for PII | 04 | missing/partial |
| `3-app/10-deployment` | Concurrency model per language; gunicorn CMD + `--max-requests` jitter + timeouts + `--preload` trade-off; workers = CPU limit; immutable tags; Dockerfile checklist (multi-stage, pinned base, no dev deps in runtime) | 03, 05, template | missing/partial |
| `4-feature/01` | Adapter-modules pattern (`modules/` + `base.py` + one output shape); ~10 files → subdivide inside the folder | 07 | missing |
| `4-feature/02` | api layer owns paths, zod at the boundary, error normalisation, query keys; `api/` grouped by backend vocabulary; pages mirror URL tree, ~50 lines, router imports pages only | 07 | partial |
| `4-feature/03` | No global `types.ts`/`types.py`; never import DTOs across domains — duplicate | 07 | missing |
| `4-feature/04` | Typography allowlist; `frontend-design` precedence; fold repeated utilities into a variant on the second use; feature code = primitives + layout glue; hook-safe grep form; screenshot light+dark before done | 04, 07, 06 | missing |
| `4-feature/05` | Cap exclusions (generated, vendored, fixtures) + "comment why"; rule of three with counter-rules; `helpers/`/`utils/`/`common/` banned, `shared/` at 3+; split signals | 07 | missing/partial |
| `snippets_old/claude` | Structure-contract block (recorded choices, skeletons, tripwires, evolution, escalation); styling block in the brief; stack table | `template/AGENTS.md` | missing |
| `snippets_old/python` | `alembic_helpers.run_sql` + shim revision | `template/apps/database/postgres/` | missing |
| `snippets_old/frontend/light-dark.css` | Theme switch stylesheet + toggle | `packages/ui/src/styles/` | partial |
| `snippets_old/scripts` | — | — | covered (template is a superset; `list_configs` dropped by design) |

Drift the agent found that is already fixed this session: 06 gate pointer, 05 verb table (`typecheck`, `gate <rung>`). Still open: prod settings in `compose.base.yaml` (checklist has no instance to point at).
