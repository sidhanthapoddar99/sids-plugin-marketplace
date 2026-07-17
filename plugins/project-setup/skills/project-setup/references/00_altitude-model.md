# The altitude model — four levels of structural decisions

Every structural decision has an **altitude**. Classify it first; then open that level's index; the index routes to the 1–3 topical references that resolve it. This file defines the levels, the principles they share, the master tripwire table, **the ownership map (decision axis → owner file)**, and the evolution machinery that keeps structure alive after bootstrap. It is the spine: everything else cites it, and it restates nothing that a topical file owns.

## The four levels

| Level | Scope | Decides | Binds when | Delivered via |
|---|---|---|---|---|
| **L1 Ecosystem** (`references/1-ecosystem/00_index.md`) | across repos | repo cardinality + boundaries, sibling roles, docs placement, cross-repo contracts | rarely — product inception, repo-split moments | questions → each repo's CLAUDE.md records its role + siblings |
| **L2 Repo** (`references/2-repo/00_index.md`) | one repo | layout, app count + grouping topology, runtime triad (`ctl`/docker/mise), env + config flow, root contract, deployment, DB engines | at bootstrap | questions → the tree itself + the CLAUDE.md repo block |
| **L3 App** (`references/3-app/00_index.md`) | one app or package | internal skeleton (backend domains, frontend `src/`, package exports), stack choice, shared-lib placement, migration style + owner, per-app DB usage, AI surface, security tier, app packaging | when each app is created | derived from L2 + few questions → the CLAUDE.md structure block |
| **L4 Feature** (`references/4-feature/00_index.md`) | folders, files, content | feature-folder shape, subdivision, type/DTO placement, api-layer internals, pages ↔ URLs, styling, file caps | **continuously, during development** | never asked — doctrine + tripwires installed in CLAUDE.md, enforced by audit |

The binding-time column is the load-bearing one. L1/L2 can be asked at bootstrap; L3 binds per-app; **L4 can never be a bootstrap question** — it only holds if it's installed as always-loaded doctrine (CLAUDE.md blocks) and re-checked (audits). A convention delivered at the wrong time doesn't hold, no matter how good it is.

## Routing — classify the altitude first

| Decision sounds like | Level |
|---|---|
| "should the docs / this component get its own repo", "how do these repos share X" | L1 |
| "monorepo or polyrepo", "add a second backend", "where does compose live", "which database engine", "how is this deployed", "root is cluttered" | L2 |
| "what goes inside this app", "where do shared libs live", "how do migrations work here", "does this app get `pages/`", "which framework/stack for this app", "this app calls LLMs — where does that code go", "where do rate limits live" | L3 |
| "where does this file/type go", "this folder is getting big", "can I call fetch here", "which text size" | L4 |

Ties go **up**: when a decision spans two levels, the higher level owns it, because decisions bind downward. Boundary assignments:

| Boundary decision | Owner | Note |
|---|---|---|
| deployed vs distributed (Layout 06) | L1 | it defines what the repo *is* to external consumers (`references/1-ecosystem/repo-boundaries.md`) |
| grouping topology (flat / plane-grouped / hybrid) | L2 | shapes the tree; L3 inherits its slot (`references/2-repo/01-layouts/00_grouping-topology.md`) |
| workspace rooting (repo root vs group folder) | L2 | part of the root contract, owned with topology (`references/2-repo/01-layouts/00_grouping-topology.md`) |
| package **placement** (which scope) | L2/L3 interface | rule: lowest level containing all consumers (`references/2-repo/01-layouts/00_grouping-topology.md`) |
| package **internals** (export surface, skeleton) | L3 | `references/3-app/05-package/00_shared-packages.md` |
| DB **engine** choice + provisioning | L2 | infra is repo-level (`references/3-app/04-database/00_provisioning.md`) |
| DB **usage** conventions per app | L3 | `references/3-app/04-database/` |
| deployment **stack** (compose, proxy, expose tiers, readiness checklist) | L2 | `references/2-repo/04-docker/` |
| deployment **per app** (worker model, Dockerfile packaging, healthcheck endpoint) | L3 | `references/3-app/10-deployment/` |
| migration style + DDL owner | L3 | escalates to L2 when two backends share one DB (`references/3-app/02-backend/02_two-plane-split.md`) |

## The five principles — stated once, instantiated per level

1. **Skeleton firm, contents vary.** Every container promises a hard skeleton at its top level; below it, project-specific. L2: root inventory. L3: `src/` layers, `app/` domains. L4: `{router,service,repository,models}.py`, `layout/<shell>/`.
2. **Flat until a threshold, then group.** Grouping layers are earned by count or by a settled model — never pre-created, never skipped past the tripwire. L2: `apps/` planes. L3: backend domains. L4: feature-folder subdivision.
3. **Code lives at the lowest level that contains all its consumers.** L2: package scope (client group vs root `packages/`). L3: domain-shared vs `core/`. L4: feature-internal types vs `api/` vs `packages/types`.
4. **The root is an index, not a runtime.** Roots orchestrate and link inward; runtimes live inside folders. L2: repo root (`references/2-repo/02-root-hygiene/00_root-and-hygiene.md`). L3: a package's `index.ts` export surface. L4: thin `pages/` routing into `features/`.
5. **Structure is versioned and re-openable.** Chosen variants + tripwire numbers are recorded in CLAUDE.md; when the model settles or a number trips, structure reconciles. All levels.

When a situation has no written rule, resolve it from these principles at the right altitude — then record the resolution.

## Master tripwire table

Structure gets numbers, like the file caps — checkable while working, not vibes. Crossing one obligates **either the restructure or a recorded deferral** (one line in CLAUDE.md: what, why, until when). Silent crossing is the failure mode. **These numbers live here and in the owner file only; everywhere else cites by ID.**

| # | Tripwire | Threshold | Action | Owner |
|---|---|---|---|---|
| T1 | apps in a flat `apps/` hiding planes | 2+ frontends AND (2+ backends OR frontend-only packages) | plane-grouped topology | L2 (`references/2-repo/01-layouts/00_grouping-topology.md`) |
| T2 | feature folders per app | ~8–10 | introduce a domain layer | L3 (`references/3-app/02-backend/01_domain-grouping.md`) |
| T3 | source files per feature folder | ~10 | subdivide the feature | L4 (frontend: `references/4-feature/02_api-and-pages.md`; backend twin: `references/4-feature/01_feature-folders.md`) |
| T4 | components flat in a ui package | ~15 | group by component family | L3 (`references/3-app/05-package/00_shared-packages.md`) |
| T5 | lines per file | 500 hard / 300 soft | split | L4 (`references/4-feature/05_caps-and-extraction.md`) |
| T6 | lines per `pages/` file | ~50 | substance moves to `features/` | L4 (`references/4-feature/02_api-and-pages.md`) |
| T7 | `ctl` dispatcher size / needs structured state | ~150 lines | escalate to a binary | L2 (`references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md`) |
| T8 | same utility combo twice (styling) | 2 | fold into a primitive variant | L4 (`references/4-feature/04_styling-discipline.md`) |
| T9 | same logic three times | 3 | extract a shared helper | L4 (`references/4-feature/05_caps-and-extraction.md`) |
| T10 | runtime deps in a root manifest | 1 | move it into the app/package folder | L2 (`references/2-repo/02-root-hygiene/00_root-and-hygiene.md`) |

## Ownership map — decision axis → owner file

One decision, one owner file. The normative rule (variants, tripwire, audit check) lives ONLY in the owner; every other file cites it in ≤1 line + a link. This table is the index; the tree under `references/` IS the altitude model.

### L1 Ecosystem (`references/1-ecosystem/`)

| Decision axis | Owner file | Tripwire |
|---|---|---|
| L1 decision index, invariants, interfaces, audit list | `00_index.md` | — |
| mono vs poly repo; own-repo criteria; deployed-vs-distributed; escalation between them | `repo-boundaries.md` | — |
| in-repo `docs/` vs separate docs repo + handoff to the docs plugin | `docs-placement.md` | — |
| aggregator repo, env.example sync, sharing ranking (publish > pin > vendor), image registry/semver contracts, no-shared-tables | `cross-repo-contracts.md` | — |

### L2 Repo (`references/2-repo/`)

| Decision axis | Owner file | Tripwire |
|---|---|---|
| L2 decision index → owners, invariants, variants, audit list | `00_index.md` | — |
| the L2 layout picker (answers → layout + key decisions) | `references/02_decision-tree.md` | — |
| grouping topology (flat/plane-grouped/hybrid) + workspace rooting + package placement scope | `01-layouts/00_grouping-topology.md` | T1 |
| single-app repo shape | `01-layouts/01_single-app.md` | — |
| multi-app monorepo shape, backend/frontend scaling spectrum, core-vs-BFF axis | `01-layouts/02_multi-app-monorepo.md` | — |
| polyrepo aggregator repo shape | `01-layouts/03_polyrepo-aggregator.md` | — |
| ML repo shape | `01-layouts/04_ml-project.md` | — |
| Go-CLI-driven compose tree shape | `01-layouts/05_infra-orchestrator.md` | — |
| package + reference-host repo shape, publishing mechanics | `01-layouts/06_embeddable-package.md` | — |
| root-as-index, orchestration-only root manifest, single-package containment + exceptions, `.gitignore` | `02-root-hygiene/00_root-and-hygiene.md` | T10 |
| root README contract + per-service READMEs | `02-root-hygiene/01_readme-three-paths.md` | — |
| env precedence: 3 tiers + root `.env` scope + `.env.example` | `03-env-config/00_env-precedence.md` | — |
| per-backend `config.yaml` + `${VAR}` interpolation | `03-env-config/01_per-service-config.md` | — |
| build-time vs runtime + `VITE_*`/`NEXT_PUBLIC_*` no-leak | `03-env-config/02_frontend-env-isolation.md` | — |
| dev / CI / prod / Vault secrets placement + rotation | `03-env-config/03_secrets-matrix.md` | — |
| `docker/` layout + path discipline; standalone config vs `.m.` modifiers + expose tiers | `04-docker/00_docker-overview.md` | — |
| bind-mounts, `data/` layout, internal-vs-host ports, YAML anchors | `04-docker/01_docker-details.md` | — |
| `DATA_SVCS=()` DB-less topology swap | `04-docker/02_no-data-core.md` | — |
| two+ stacks sharing one docker network | `04-docker/03_multi-stack.md` | — |
| `/api/*` routing contract, Vite-proxy↔nginx pair, Traefik/expose posture | `04-docker/04_proxy-and-exposure.md` | — |
| health/readiness, graceful shutdown, limits, migrations-on-deploy checklist | `04-docker/05_production-readiness.md` | — |
| the `ctl`/scripts model + conformance floor | `05-ctl-scripts-tooling/00_script-overview.md` | — |
| command surface + skeleton + interactive `ctl up` + `scripts/*.sh` map | `05-ctl-scripts-tooling/01_script-usage.md` | — |
| opting out of mise/docker/uv/bun defaults | `05-ctl-scripts-tooling/02_script-alternatives.md` | — |
| profiles as escalation + multi-mode trees + escalate `ctl` → binary | `05-ctl-scripts-tooling/03_complex-setups.md` | T7 |
| lefthook / vscode-debugger / ci-cd tooling | `05-ctl-scripts-tooling/` (04_lefthook, 05_vscode-debugger, 06_ci-cd-future) | — |
| how mise + `ctl` + docker + env interact (the one map) | `06-runtime-environment/00_runtime-triad.md` | — |
| `.mise.toml` version contract + bare-name PATH | `06-runtime-environment/01_mise.md` | — |
| ML cloud orchestration (6 files: custom-orchestrator, spot-instances-and-checkpoints, inference-autoscaling, remote-dev-ssh-vscode, agent-ssh-access, cicd-for-ml) | `07-ml-orchestration/` | — |

(Mobile, desktop, PWA are app-kind decisions housed at L3 — see the L3 map below. DB engine choice remains an **L2 decision** (boundary table above) that is *housed* under `3-app/04-database/` next to its usage conventions.)

### L3 App (`references/3-app/`)

| Decision axis | Owner file | Tripwire |
|---|---|---|
| L3 decision index, per-app questions, invariants, audit list | `00_index.md` | — |
| the every-app contract: self-contained, no cross-app imports, app-vs-package test, must/never-contain | `01-structure-and-stack/00_app-anatomy.md` | — |
| which stack an app uses (backend lang, web framework, mobile/desktop, JS runtime; data engine routes to `04-database/00_provisioning.md`) | `01-structure-and-stack/01_stack-decision.md` | — |
| pnpm/turbo/bun config bodies, catalog, globalEnv, ctl shape | `01-structure-and-stack/02_workspaces-mechanics.md` | — |
| flat `app/` rule (run-service vs src-layout), pyproject+uv flow, top-level skeleton | `02-backend/00_app-skeleton.md` | — |
| the domain layer: naming, aggregator routers, domain-shared placement, reconcile | `02-backend/01_domain-grouping.md` | T2 |
| admin/user split decision + `apps/db` neutral owner + one-DB ownership | `02-backend/02_two-plane-split.md` | — |
| `requirements.txt` + uvenv global env for ML | `02-backend/03_ml-python-flow.md` | — |
| frontend structure: app placement + config + hard `src/` skeleton + layer import rules + workspace reconciliation + layout-shells | `03-web-app/00_app-skeleton.md` | — |
| Next/Astro variants | `03-web-app/01_framework-variants.md` | — |
| PWA = web frontend + manifest/service worker (not a separate app); PWA vs native/desktop; offline scope | `03-web-app/02_pwa.md` | — |
| DB engine choice (right floor) + infra/ vs data/ placement — repo-wide decision, housed at L3 | `04-database/00_provisioning.md` | — |
| migration style decision: Alembic vs raw-SQL vs when-not-Alembic vs no-tool; entrypoint-migrates vs one-shot vs neutral owner | `04-database/01_migrations.md` | — |
| Alembic mechanics: init recipe, ini/env.py, daily flow, docker entrypoint | `04-database/02_alembic-recipe.md` | — |
| raw-SQL mechanics: 3-file pattern, shim, helpers, drift check | `04-database/03_raw-sql-recipe.md` | — |
| per-engine usage conventions (sqlite/postgres/redis/other) | `04-database/{04_sqlite,05_postgres,06_redis,07_other-engines}.md` | — |
| package internals (ui/styles/services/types), export surface, ~15-component grouping, tailwind-config wiring | `05-package/00_shared-packages.md` | T4 |
| `tokens.css` content/location, light-dark data-attr, shadcn wiring | `05-package/01_tokens-setup.md` | — |
| embedding seams / IoC config API / per-instance mounts | `05-package/02_embeddable-seams.md` | — |
| Tauri/Electron desktop; shares web `packages/` | `06-desktop-app/00_desktop-app.md` | — |
| native iOS/Android under `apps/` | `07-mobile-app/00_mobile-app.md` | — |
| MCP server placement (app vs package), client config, local vs remote, tool versioning | `08-ai/00_mcp-servers.md` | — |
| LLM/agent integration as a provider boundary: adapter-per-provider, prompt placement, evals | `08-ai/01_agent-sdks.md` | — |
| AI key usage (backend-only, proxy route), prompt-injection posture, AI-call audit | `08-ai/02_ai-keys-and-safety.md` | — |
| edge bot/abuse protection: Cloudflare/WAF, captcha/Turnstile placement, tier decision | `09-security-hardening/00_edge-protection.md` | — |
| rate-limiting layers; app-owned per-user/per-key limits, 429 contract | `09-security-hardening/01_rate-limiting.md` | — |
| telemetry + audit: structured logs, audit events, error tracking, telemetry adapter | `09-security-hardening/02_telemetry-and-audit.md` | — |
| per-language worker model, recycling, timeouts | `10-deployment/00_serving.md` | — |
| Dockerfile-per-app packaging, image naming/tag, healthcheck contract, `.dockerignore` | `10-deployment/01_app-packaging.md` | — |

### L4 Feature (`references/4-feature/`)

| Decision axis | Owner file | Tripwire |
|---|---|---|
| L4 index, delivery via CLAUDE.md blocks, mechanical audit greps, hands-back-up rule | `00_index.md` | — |
| `{router,service,repository,models}.py` shape, feature seams, adapter-modules, backend subdivision | `01_feature-folders.md` | T3 (backend) |
| `api/` internals (endpoints, zod, error norm, query keys, domain mirroring), thin pages, URL mirroring, fetch grep, frontend subdivision | `02_api-and-pages.md` | T3 (frontend), T6 |
| all type/DTO placement, both planes | `03_types-and-contracts.md` | — |
| primitive-first styling hard rules + precedence + greps | `04_styling-discipline.md` | T8 |
| 500/300 caps, rule of three, rule of two styling, folders-by-feature, test co-location | `05_caps-and-extraction.md` | T5, T9 |

### Handoffs (`references/handoffs/`)

| Decision axis | Owner file | Tripwire |
|---|---|---|
| `.claude/` stays empty + CLAUDE.md template guidance | `claude-folder.md` | — |
| the per-installation registry of the user's real repos | `examples-registry.md` | — |

## Evolution machinery — structure after bootstrap

Bootstrap-time layout is a starting point, never a contract. Four rules keep it alive:

1. **Every choice is recorded.** The CLAUDE.md carries the chosen variants (topology, rooting, BFF/core, migration owner, any sanctioned exception) and the tripwire numbers. **Audits compare the repo against its *recorded* choices** — an unusual shape with a recorded choice is a variant; a missing record is the finding.
2. **Reconcile when the model settles.** When the product's domain model / IA is decided or meaningfully revised, code structure reconciles **within the same milestone** — not deferred indefinitely.
3. **Restructures ride consolidation windows.** Folder moves and renames batch into windows where churn already happens (schema consolidation, major refactor, pre-release reset) — import churn is paid once, not per-PR.
4. **Audits get triggers.** Run `/ps-setup audit` at roadmap-stage boundaries and whenever a tripwire is crossed — not "someday".

## Escalation — when the standard runs out

If a structural decision falls outside the recorded standard, or the standard itself seems wrong: load the `project-setup` skill and resolve it at the right level — **never improvise a new pattern inline**. The CLAUDE.md blocks are the always-loaded summary; this skill is the authority they defer to. That escalation pointer ships inside the CLAUDE.md template so every future agent knows who to ask.

## See also

- `references/1-ecosystem/00_index.md` · `references/2-repo/00_index.md` · `references/3-app/00_index.md` · `references/4-feature/00_index.md` — the per-level indexes
- `references/02_decision-tree.md` — the L2 layout picker
- `references/01_question-flow.md` — the level-ordered question flow
- `references/5-examples/00_index.md` — annotated whole-project trees mapping example ↔ layout ↔ variants
