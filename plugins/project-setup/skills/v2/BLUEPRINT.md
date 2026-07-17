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
| `00_charter.md` | L1 decision index, invariants, interfaces, audit list — pointers only | `levels/01_ecosystem.md` |
| `repo-boundaries.md` | mono vs poly; own-repo criteria; deployed-vs-distributed; escalation triggers between them | `levels/01_ecosystem.md`, decision-tree step 1, layout 03 (the WHEN half), layout 06 (the WHEN half) |
| `docs-placement.md` | in-repo `docs/` vs separate docs repo + the handoff protocol to the docs plugin | `integrations/docs-integration.md` (whole file moves here; placement decision + mechanics) |
| `cross-repo-contracts.md` | aggregator repo, env.example sync, sharing ranking (publish > pin > vendor), image registry/semver contracts, no-shared-tables rule | `levels/01_ecosystem.md`, layout 03 (contract parts) |

### 2-repo/

| v2 path | Owns | Sources |
|---|---|---|
| `00_charter.md` | L2 decision index → owners; invariants; variants list; audit list | `levels/02_repo.md` |
| `layouts/01_single-app.md` | the one-app repo shape (repo-level tree only; src-vs-app detail = 1 line + link) | same-named |
| `layouts/02_multi-app-monorepo.md` | the multi-app shape, backend/frontend scaling spectrum, mesh end, core-vs-BFF axis; topology = 1 line + link to grouping-topology.md | same-named (topology section MOVES OUT) |
| `layouts/03_polyrepo-aggregator.md` | the aggregator repo's SHAPE (when-polyrepo lives in 1-ecosystem) | `layouts/03_polyrepo-with-aggregator.md` |
| `layouts/04_ml-project.md` | ML repo shape | same-named |
| `layouts/05_infra-orchestrator.md` | Go-CLI-driven compose tree shape | same-named |
| `layouts/06_embeddable-package.md` | package+reference-host repo shape, publishing mechanics, single-artifact delivery (when-distributed lives in 1-ecosystem; embedding seams detail in 3-app) | `layouts/06_…`, keep publishing here |
| `grouping-topology.md` | **NEW OWNER**: flat/plane-grouped/hybrid variants + decision rule + workspace rooting (JS-only vs polyglot) + package placement scope — one decision cluster, one file | layout 02 § topology, `root-and-hygiene.md` § rooting, `multi-frontend-workspaces.md` § rooting+scope |
| `root-and-hygiene.md` | root-as-index, orchestration-only root manifest, single-package containment + exceptions, `.gitignore` doctrine (rooting = 1 line + link to grouping-topology) | `repo-setup/root-and-hygiene.md` |
| `readme-three-paths.md` | root README contract + per-service READMEs | same-named |
| `runtime/overview.md` `runtime/mise.md` `runtime/docker-overview.md` `runtime/docker-details.md` `runtime/multi-stack.md` `runtime/script-overview.md` `runtime/script-usage.md` `runtime/script-alternatives.md` `runtime/no-data-core.md` `runtime/complex-setups.md` | as today (already well-owned); migrate + fix links + scope-check | `repo-setup/runtime/*` |
| `env-and-config/env-precedence.md` `…/per-service-config.md` `…/frontend-env-isolation.md` `…/secrets-matrix.md` | as today | `repo-setup/env-and-config/*` |
| `databases-provisioning.md` | engine choice (right floor) + infra/ vs data/ placement — ONE file (usage conventions live in 3-app) | `architecture/database/choosing-a-database.md` + `infra-vs-data-folder.md` |
| `deployment/proxy-and-exposure.md` | the `/api/*` routing contract, Vite-proxy↔nginx pair, Traefik/expose posture | `architecture/frontend/vite-proxy-nginx-pair.md` + `api-prefix-routing.md` |
| `deployment/production-readiness.md` | health/readiness, graceful shutdown, limits, migrations-on-deploy checklist (worker model = link to 3-app serving) | `architecture/production/production-readiness.md` |
| `platform/mobile.md` `platform/desktop.md` | as today | `architecture/platform/*` |
| `ml-orchestration/` (6 files: custom-orchestrator, spot-instances-and-checkpoints, inference-autoscaling, remote-dev-ssh-vscode, agent-ssh-access, cicd-for-ml — tool-agnostic `scripts/cloud/` doctrine, no third-party orchestrator) | as today | `architecture/ml-orchestration/*` |
| `tooling/lefthook.md` `tooling/vscode-debugger.md` `tooling/ci-cd-future.md` | as today | `repo-setup/tooling/*` |

### 3-app/

| v2 path | Owns | Sources |
|---|---|---|
| `00_charter.md` | L3 decision index, per-app questions, invariants, audit list | `levels/03_app.md` |
| `backend/app-skeleton.md` | flat `app/` rule (run-service vs src-layout), pyproject+uv flow, the top-level skeleton (`main.py`, `core/`, feature folders) | `architecture/backend/pyproject-uv-sync-for-apps.md`, skeleton bits of layouts |
| `backend/domain-grouping.md` | the domain layer: tripwire T2, ownership-noun naming, aggregator routers, domain-shared placement, reconcile/consolidation (feature-folder INTERNALS → 4-feature) | `architecture/modularity/domain-grouping-tripwire.md` (split: L3 half) |
| `backend/migrations.md` | **NEW OWNER (decision)**: Alembic default vs raw-SQL vs when-not-Alembic vs no-tool; entrypoint-migrates vs one-shot vs neutral owner | decision halves of `alembic-default.md`, `alembic-with-raw-sql.md`, `when-not-alembic.md` |
| `backend/alembic-recipe.md` | mechanics: init recipe, ini/env.py, daily flow, docker entrypoint | `alembic-default.md` (recipe half) |
| `backend/raw-sql-recipe.md` | mechanics: 3-file pattern, shim, helpers, sqlx drift check | `alembic-with-raw-sql.md` (recipe half) |
| `backend/two-plane-split.md` | admin/user split decision + `apps/db` neutral owner + one-DB ownership | `architecture/backend/two-plane-split.md` |
| `backend/serving.md` | per-language worker model, recycling, timeouts (split OUT of production/) | `architecture/production/app-server-and-workers.md` |
| `backend/ml-python-flow.md` | requirements.txt + uvenv global env for ML | `architecture/backend/requirements-uvenv-for-ml.md` |
| `frontend/app-skeleton.md` | **THE answer to "structure of the frontend"**: app placement + config files + the hard `src/` skeleton + layer import rules + workspace-reconciliation (local vs packages) + layout-shells rule (api/pages/types INTERNALS → 4-feature) | `architecture/frontend/single-frontend.md` + `intra-app-structure.md` MERGED (L3 halves) |
| `frontend/workspaces-mechanics.md` | mechanics only: pnpm/turbo/bun config bodies, catalog, globalEnv, ctl shape (decisions → grouping-topology) | `multi-frontend-workspaces.md` (mechanics half) |
| `frontend/shared-packages.md` | package internals: what lives in ui/styles/services/types, export surface, ~15-component grouping (T4), tailwind-config wiring | `shared-ui-package.md` + `intra-app-structure.md` § packages |
| `frontend/tokens-setup.md` | tokens.css content/location, light-dark data-attr, shadcn wiring (USAGE discipline → 4-feature) | `design-tokens.md`, `light-dark-data-attr.md`, `shadcn-tailwind.md` (merge; keep sub-sections) |
| `frontend/framework-variants.md` | Next/Astro variants | `nextjs-astro-variants.md` |
| `frontend/embeddable-seams.md` | embedding seams / IoC config API / per-instance mounts (repo shape + publishing stay in layout 06) | `architecture/frontend/embeddable-package-and-reference-host.md` |
| `database-usage/postgres.md` `…/redis.md` `…/sqlite.md` `…/other-engines.md` | per-engine usage conventions | `architecture/database/{postgres,redis,sqlite,mongodb-neo4j-seaweed}-…` |

### 4-feature/

| v2 path | Owns | Sources |
|---|---|---|
| `00_charter.md` | L4 index, the delivery mechanism (CLAUDE.md blocks), mechanical audit greps, hands-back-up rule | `levels/04_feature.md` |
| `feature-folders.md` | `{router,service,repository,models}.py` shape, feature seams (lifecycle boundaries, merge rule), adapter-modules pattern, T3 subdivision (backend) | `domain-grouping-tripwire.md` (L4 half) |
| `api-and-pages.md` | `api/` internals (endpoints, zod, error norm, query keys, domain mirroring, T6 thin pages, URL mirroring, fetch grep) + frontend feature subdivision | `intra-app-structure.md` (L4 half) |
| `types-and-contracts.md` | ALL type/DTO placement, both planes: models.py DTOs, no cross-domain imports, no shared models pkg, zod-inferred types, packages/types re-export, no types.ts dump | `domain-grouping-tripwire.md` § DTO + `intra-app-structure.md` § types |
| `styling-discipline.md` | the primitive-first hard rules + precedence + greps (unchanged in substance) | `architecture/frontend/styling-discipline.md` |
| `caps-and-extraction.md` | 500/300 caps (T5), rule of three (T9) / rule of two styling (T8), folders-by-feature rule + kind-folder exceptions, test co-location | `modularity/file-size-caps.md` + `extract-on-third-use.md` + `folders-by-feature.md` |

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
