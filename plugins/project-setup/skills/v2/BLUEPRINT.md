# v2 build blueprint — level-first restructure with single ownership

Build spec for the v2 references library, staged in `skills/v2/`. The live skill at `skills/project-setup/` stays untouched and serves as SOURCE material. At swap time, `v2/SKILL.md` + `v2/references/` replace the originals and this file is deleted.

## Design rules (every author and validator enforces these)

1. **One decision, one owner file.** Each decision axis has exactly ONE file holding the normative rule, its variants, its tripwire, its audit check. Every other file may mention it in ≤1 line + a link ("owned by X — don't restate"). Peer-level duplication is a defect.
2. **The tree IS the altitude model.** Folders are levels (`1-ecosystem/ … 5-examples/`). A file contains only content at its level; content at another altitude moves to that level's owner and is linked.
3. **Decision files vs mechanics files.** Decision files: when/what to decide, variants, tripwires, audit. Mechanics files: recipes (setup steps, config bodies) owned by exactly one decision file, containing zero decisions.
4. **Hierarchical restatement is allowed** (SKILL.md strong defaults, charters, CLAUDE.md blocks summarize + link). **Peer restatement is not.**
5. **Project-agnostic + forward-looking.** No personal repos, no machine paths, no past-mistake narrative. Direct actionable doctrine: what to do, what to ask. Generic worked examples only.
6. **Information-dense, not crowded.** Match the existing reference style: H1, terse intro naming what the file owns, tables, generic trees, "Audit checks" / "Anti-patterns" / "See also" sections. No filler, no repetition-as-emphasis.
7. **Tripwire numbers live in the master table** (`00_altitude-model.md`) and in their owner file; everywhere else cite by reference (e.g. "tripwire T2").
8. **Links use post-swap paths** — `references/2-repo/…` (NOT `v2/references/…`), relative to the skill folder, exactly like the current library.
9. Compose/`ctl` doctrine is already correct in the current library — migrate it faithfully (profile-less two axes, conformance floor); do not redesign it.

## Target tree + ownership (S = source files under the LIVE skill's `references/`)

### Root (spine)

| v2 path | Owns | Sources |
|---|---|---|
| `SKILL.md` | skill orchestration, strong defaults (summaries+links), workflows A/B, audit mode, the FILE MAP (must match this tree exactly) | live `SKILL.md` |
| `references/00_altitude-model.md` | the 4+1 levels, 5 principles, MASTER TRIPWIRE TABLE, evolution machinery, **the OWNERSHIP TABLE** (decision axis → owner file → level) generated from this blueprint | `levels/00_altitude-model.md` |
| `references/01_question-flow.md` | the level-ordered interview; ALWAYS-ask list | `01_question-flow.md` (update paths only + any new refs) |
| `references/02_decision-tree.md` | the L2 layout picker | `00_decision-tree.md` (renumbered; strip content now owned elsewhere: app/-vs-src detail → link 3-app owners; compose footprint → link docker-overview) |

### 1-ecosystem/

| v2 path | Owns | Sources |
|---|---|---|
| `00_index.md` | L1 decision index, invariants, interfaces, audit list — pointers only (renamed from `00_charter.md`) | `levels/01_ecosystem.md` |
| `repo-boundaries.md` | mono vs poly; own-repo criteria; deployed-vs-distributed; escalation triggers between them | `levels/01_ecosystem.md`, decision-tree step 1, layout 03 (the WHEN half), layout 06 (the WHEN half) |
| `docs-placement.md` | in-repo `docs/` vs separate docs repo + the handoff protocol to the docs plugin | `integrations/docs-integration.md` (whole file moves here; placement decision + mechanics) |
| `cross-repo-contracts.md` | aggregator repo, env.example sync, sharing ranking (publish > pin > vendor), image registry/semver contracts, no-shared-tables rule | `levels/01_ecosystem.md`, layout 03 (contract parts) |

### 2-repo/

| v2 path | Owns | Sources |
|---|---|---|
| `00_index.md` | L2 decision index → owners; invariants; variants list; audit list | `levels/02_repo.md` |
| `01-layouts/00_grouping-topology.md` | **NEW OWNER**: flat/plane-grouped/hybrid variants + decision rule + workspace rooting (JS-only vs polyglot) + package placement scope — one decision cluster, one file (grouped with layouts: decided with the layout) | layout 02 § topology, `00_root-and-hygiene.md` § rooting, `multi-frontend-workspaces.md` § rooting+scope |
| `01-layouts/01_single-app.md` | the one-app repo shape (repo-level tree only; src-vs-app detail = 1 line + link) | same-named |
| `01-layouts/02_multi-app-monorepo.md` | the multi-app shape, backend/frontend scaling spectrum, mesh end, core-vs-BFF axis; topology = 1 line + link to grouping-topology | same-named (topology section MOVES OUT) |
| `01-layouts/03_polyrepo-aggregator.md` | the aggregator repo's SHAPE (when-polyrepo lives in 1-ecosystem) | `layouts/03_polyrepo-with-aggregator.md` |
| `01-layouts/04_ml-project.md` | ML repo shape | same-named |
| `01-layouts/05_infra-orchestrator.md` | Go-CLI-driven compose tree shape | same-named |
| `01-layouts/06_embeddable-package.md` | package+reference-host repo shape, publishing mechanics, single-artifact delivery (when-distributed lives in 1-ecosystem; embedding seams detail in 3-app) | `layouts/06_…`, keep publishing here |
| `02-root-hygiene/00_root-and-hygiene.md` | root-as-index, orchestration-only root manifest, single-package containment + exceptions, `.gitignore` doctrine (rooting = 1 line + link to grouping-topology) | `repo-setup/00_root-and-hygiene.md` |
| `02-root-hygiene/01_readme-three-paths.md` | root README contract + per-service READMEs | same-named |
| `03-env-config/00_env-precedence.md` `…/01_per-service-config.md` `…/02_frontend-env-isolation.md` `…/03_secrets-matrix.md` | as today | `repo-setup/env-and-config/*` |
| `04-docker/00_docker-overview.md` `…/01_docker-details.md` `…/02_no-data-core.md` `…/03_multi-stack.md` | docker/ layout + path discipline, bind-mounts/ports, DB-less topology swap, multi-stack (as today); migrate + fix links + scope-check | `repo-setup/runtime/*` (docker + no-data-core) |
| `04-docker/04_proxy-and-exposure.md` | the `/api/*` routing contract, Vite-proxy↔nginx pair, Traefik/expose posture | `architecture/frontend/vite-proxy-nginx-pair.md` + `api-prefix-routing.md` |
| `04-docker/05_production-readiness.md` | health/readiness, graceful shutdown, limits, migrations-on-deploy checklist (worker model = link to 3-app serving) | `architecture/production/05_production-readiness.md` |
| `05-ctl-scripts-tooling/00_script-overview.md` `…/01_script-usage.md` `…/02_script-alternatives.md` `…/03_complex-setups.md` | the ctl/scripts model + usage + opt-out alternatives + complex-setups escalation (as today); migrate + fix links + scope-check | `repo-setup/runtime/*` (script + complex-setups) |
| `05-ctl-scripts-tooling/04_lefthook.md` `…/05_vscode-debugger.md` `…/06_ci-cd-future.md` | as today | `repo-setup/tooling/*` |
| `06-runtime-environment/00_runtime-triad.md` `06-runtime-environment/01_mise.md` | the ONE runtime-interaction map (mise+ctl+docker+env) + `.mise.toml` version contract (as today; `overview.md` renamed → `00_runtime-triad.md`) | `repo-setup/runtime/*` (overview + mise) |
| `07-ml-orchestration/` (6 files: custom-orchestrator, spot-instances-and-checkpoints, inference-autoscaling, remote-dev-ssh-vscode, agent-ssh-access, cicd-for-ml — tool-agnostic `scripts/cloud/` doctrine, no third-party orchestrator) | as today — renamed from `07-platform/ml-orchestration/` and flattened up one level | `architecture/ml-orchestration/*` |

The former `07-platform/` also held DB-provisioning, mobile, desktop, and PWA — **all four moved DOWN to L3 `3-app/`** (they are app-kind decisions); `07-platform/` no longer exists. See the 3-app section for their new homes.

### 3-app/

| v2 path | Owns | Sources |
|---|---|---|
| `00_index.md` | L3 decision index, per-app questions, invariants, audit list (renamed from `00_charter.md`) | `levels/03_app.md` |
| `01-structure-and-stack/00_app-anatomy.md` | **NEW**: the every-app contract — self-contained, no cross-app imports, app-vs-package test, must/never contain | newly authored |
| `01-structure-and-stack/01_stack-decision.md` | **NEW (decision)**: which lang/framework/runtime/engine an app uses, per kind + criteria; one line + link per owned option | newly authored |
| `01-structure-and-stack/02_workspaces-mechanics.md` | mechanics: pnpm/turbo/bun config bodies, catalog, globalEnv, ctl shape (moved from `frontend/workspaces-mechanics.md`; decisions → grouping-topology) | `multi-frontend-workspaces.md` (mechanics half) |
| `02-backend/00_app-skeleton.md` | flat `app/` rule (run-service vs src-layout), pyproject+uv flow, top-level skeleton (`main.py`, `core/`, feature folders) | `architecture/backend/pyproject-uv-sync-for-apps.md`, skeleton bits of layouts |
| `02-backend/01_domain-grouping.md` | the domain layer: T2, ownership-noun naming, aggregator routers, domain-shared placement (feature-folder INTERNALS → 4-feature) | `architecture/modularity/domain-grouping-tripwire.md` (L3 half) |
| `02-backend/02_two-plane-split.md` | admin/user split decision + `apps/db` neutral owner + one-DB ownership | `architecture/backend/two-plane-split.md` |
| `02-backend/03_ml-python-flow.md` | requirements.txt + uvenv global env for ML | `architecture/backend/requirements-uvenv-for-ml.md` |
| `03-web-app/00_app-skeleton.md` | **THE answer to "structure of the frontend"**: app placement + config + hard `src/` skeleton + import rules + workspace reconciliation + layout-shells (api/pages/types INTERNALS → 4-feature) | `architecture/frontend/single-frontend.md` + `intra-app-structure.md` MERGED (L3 halves) |
| `03-web-app/01_framework-variants.md` | Next/Astro variants | `nextjs-astro-variants.md` |
| `03-web-app/02_pwa.md` | PWA = existing web frontend + manifest/service worker (not a separate app); PWA vs native/desktop; offline scope + push reality check (**MOVED DOWN** from L2 `07-platform/`) | newly authored |
| `04-database/00_provisioning.md` | engine choice (right floor) + infra/ vs data/ placement — repo-wide decision now housed at L3 (**MOVED DOWN** from L2 `07-platform/`) | `architecture/database/choosing-a-database.md` + `infra-vs-data-folder.md` |
| `04-database/01_migrations.md` | **NEW OWNER (decision)**: Alembic vs raw-SQL vs when-not-Alembic vs no-tool; entrypoint-migrates vs one-shot vs neutral owner (moved from `backend/migrations.md`) | decision halves of `alembic-default.md`, `alembic-with-raw-sql.md`, `when-not-alembic.md` |
| `04-database/02_alembic-recipe.md` | mechanics: init recipe, ini/env.py, daily flow, docker entrypoint (moved from `backend/`) | `alembic-default.md` (recipe half) |
| `04-database/03_raw-sql-recipe.md` | mechanics: 3-file pattern, shim, helpers, sqlx drift check (moved from `backend/`) | `alembic-with-raw-sql.md` (recipe half) |
| `04-database/04_sqlite.md` `05_postgres.md` `06_redis.md` `07_other-engines.md` | per-engine usage conventions (moved from `database-usage/`) | `architecture/database/{sqlite,postgres,redis,mongodb-neo4j-seaweed}-…` |
| `05-package/00_shared-packages.md` | package internals: ui/styles/services/types, export surface, ~15-component grouping (T4), tailwind-config wiring (moved from `frontend/`) | `shared-ui-package.md` + `intra-app-structure.md` § packages |
| `05-package/01_tokens-setup.md` | tokens.css content/location, light-dark data-attr, shadcn wiring (USAGE → 4-feature; moved from `frontend/`) | `design-tokens.md`, `light-dark-data-attr.md`, `shadcn-tailwind.md` |
| `05-package/02_embeddable-seams.md` | embedding seams / IoC config API / per-instance mounts (repo shape + publishing → layout 06; moved from `frontend/`) | `architecture/frontend/embeddable-package-and-reference-host.md` |
| `06-desktop-app/00_desktop-app.md` | Tauri (default) / Electron; reuses web `packages/` (**MOVED DOWN** from L2 `07-platform/`; extended with a packages-reuse section) | `architecture/platform/desktop*` |
| `07-mobile-app/00_mobile-app.md` | native iOS (Swift) + Android (Kotlin) under `apps/` (**MOVED DOWN** from L2 `07-platform/`) | `architecture/platform/mobile*` |
| `08-ai/00_mcp-servers.md` | **NEW**: MCP server placement (app vs package), `.mcp.json` config, local stdio vs remote HTTP, tool-surface versioning | newly authored |
| `08-ai/01_agent-sdks.md` | **NEW**: LLM code as a provider boundary — adapter-per-provider (cites the L4 owner), prompt placement, streaming isolation, evals, SDK defaults | newly authored |
| `08-ai/02_ai-keys-and-safety.md` | **NEW**: AI key USAGE (backend-only, proxy route), prompt-injection posture, AI-call audit (key STORAGE → `2-repo/03-env-config/03_secrets-matrix.md`) | newly authored |
| `09-security-hardening/00_edge-protection.md` | **NEW**: bot/abuse — Cloudflare/WAF posture, Turnstile/captcha placement (backend verify), route + tier decision (edge infra stays L2) | newly authored |
| `09-security-hardening/01_rate-limiting.md` | **NEW**: layers; app OWNS per-user/per-key limits (Redis-backed when multi-instance); 429 + Retry-After (proxy connection limits stay L2) | newly authored |
| `09-security-hardening/02_telemetry-and-audit.md` | **NEW**: structured request logs, audit events, error tracking, telemetry adapter (opt-out), no secrets/PII in logs | newly authored |
| `10-deployment/00_serving.md` | per-language worker model, recycling, timeouts (moved from `backend/serving.md`) | `architecture/production/app-server-and-workers.md` |
| `10-deployment/01_app-packaging.md` | **NEW**: Dockerfile-per-app (multi-stage, non-root, pinned base), image naming/tag, healthcheck contract, `.dockerignore` (orchestration → `2-repo/04-docker/`) | newly authored |

**3-app/ counts:** 32 files across `00_index.md` + folders `01`–`10`. **9 are newly authored** — 2 in `01-structure-and-stack/` (app-anatomy, stack-decision), 3 in `08-ai/`, 3 in `09-security-hardening/`, 1 in `10-deployment/` (app-packaging). 4 moved DOWN from L2 `07-platform/` (provisioning, pwa, desktop, mobile); the remaining files are renames within 3-app. Whole library: **89 files** under `references/` (was 80; +9 new).

### 4-feature/

| v2 path | Owns | Sources |
|---|---|---|
| `00_index.md` | L4 index, the delivery mechanism (CLAUDE.md blocks), mechanical audit greps, hands-back-up rule (renamed from `00_charter.md`) | `levels/04_feature.md` |
| `01_feature-folders.md` | `{router,service,repository,models}.py` shape, feature seams (lifecycle boundaries, merge rule), adapter-modules pattern, T3 subdivision (backend) | `domain-grouping-tripwire.md` (L4 half) |
| `02_api-and-pages.md` | `api/` internals (endpoints, zod, error norm, query keys, domain mirroring, T6 thin pages, URL mirroring, fetch grep) + frontend feature subdivision | `intra-app-structure.md` (L4 half) |
| `03_types-and-contracts.md` | ALL type/DTO placement, both planes: models.py DTOs, no cross-domain imports, no shared models pkg, zod-inferred types, packages/types re-export, no types.ts dump | `domain-grouping-tripwire.md` § DTO + `intra-app-structure.md` § types |
| `04_styling-discipline.md` | the primitive-first hard rules + precedence + greps (unchanged in substance) | `architecture/frontend/styling-discipline.md` |
| `05_caps-and-extraction.md` | 500/300 caps (T5), rule of three (T9) / rule of two styling (T8), folders-by-feature rule + kind-folder exceptions, test co-location | `modularity/file-size-caps.md` + `extract-on-third-use.md` + `folders-by-feature.md` |

### 5-examples/

Complete, ANONYMIZED, annotated project trees — every folder/file commented with its purpose; each ends with "which references govern each part" links. Generic product domains; no real names.

| v2 path | Shows |
|---|---|
| `00_index.md` | what the examples are, how to read them, mapping example ↔ layout ↔ key variants |
| `01_single-cli.md` | Layout 01: a distributable CLI tool (src-layout, minimal ctl, no compose) |
| `02_canonical-1be-1fe.md` | Layout 02 flat: FastAPI + Vite, full runtime triad, tokens, alembic, the whole canonical stack — the flagship example |
| `03_two-plane-monorepo.md` | Layout 02 plane-grouped: apps/server/{api-platform,api-admin} + apps/db + apps/client/{platform,admin,packages/} workspace-rooted at client/; domains inside a backend; full src/ skeleton inside a frontend |
| `04_ml-training-project.md` | Layout 04: uvenv, configs/, scripts/cloud/, checkpoints |
| `05_polyrepo-aggregator.md` | Layout 03: three service repos + the -deploy aggregator (env sync, image-based compose) |
| `06_embeddable-package.md` | Layout 06: packages/editor product + react-less core + reference host |

### handoffs/

| v2 path | Owns | Sources |
|---|---|---|
| `claude-folder.md` | `.claude/` stays empty + CLAUDE.md template guidance | `integrations/claude-folder.md` |
| `examples-registry.md` | the per-installation registry of the user's real repos (never invent paths) | `integrations/examples-index.md` |

(Docs handoff lives at `1-ecosystem/docs-placement.md`.)

## Author notes

- Charters are thin (≤1 page): decision list → owner links, invariants, variants, tripwires by ID, audit list. They never restate a rule.
- Where a source file is split across levels, EACH half links to the other ("usage rules: see …").
- The SKILL.md file map, the ownership table in `00_altitude-model.md`, and this blueprint must agree exactly.
- `assets/snippets/` and `commands/ps-setup.md` are NOT rebuilt here; at swap time only their reference paths get updated.
