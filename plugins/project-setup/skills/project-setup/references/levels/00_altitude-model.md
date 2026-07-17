# The altitude model — four levels of structural decisions

Every structural decision has an **altitude**. Classify it first; then open that level's charter; the charter routes to the 1–3 topical references that resolve it. This file defines the levels, the principles they share, the master tripwire table, and the evolution machinery that keeps structure alive after bootstrap.

## The four levels

| Level | Scope | Decides | Binds when | Delivered via |
|---|---|---|---|---|
| **L1 Ecosystem** (`levels/01_ecosystem.md`) | across repos | repo cardinality + boundaries, sibling roles, docs placement, cross-repo contracts | rarely — product inception, repo-split moments | questions → each repo's CLAUDE.md records its role + siblings |
| **L2 Repo** (`levels/02_repo.md`) | one repo | layout, app count + grouping topology, runtime triad (`ctl`/docker/mise), env + config flow, root contract, deployment, DB engines | at bootstrap | questions → the tree itself + the CLAUDE.md repo block |
| **L3 App** (`levels/03_app.md`) | one app or package | internal skeleton (backend domains, frontend `src/`, package exports), shared-lib placement, migration style + owner, per-app DB usage | when each app is created | derived from L2 + few questions → the CLAUDE.md structure block |
| **L4 Feature** (`levels/04_feature.md`) | folders, files, content | feature-folder shape, subdivision, type/DTO placement, api-layer internals, pages ↔ URLs, styling, file caps | **continuously, during development** | never asked — doctrine + tripwires installed in CLAUDE.md, enforced by audit |

The binding-time column is the load-bearing one. L1/L2 can be asked at bootstrap; L3 binds per-app; **L4 can never be a bootstrap question** — it only holds if it's installed as always-loaded doctrine (CLAUDE.md blocks) and re-checked (audits). A convention delivered at the wrong time doesn't hold, no matter how good it is.

## Routing — classify the altitude first

| Decision sounds like | Level |
|---|---|
| "should the docs / this component get its own repo", "how do these repos share X" | L1 |
| "monorepo or polyrepo", "add a second backend", "where does compose live", "which database engine", "how is this deployed", "root is cluttered" | L2 |
| "what goes inside this app", "where do shared libs live", "how do migrations work here", "does this app get `pages/`" | L3 |
| "where does this file/type go", "this folder is getting big", "can I call fetch here", "which text size" | L4 |

Ties go **up**: when a decision spans two levels, the higher level owns it, because decisions bind downward. Boundary assignments:

| Boundary decision | Owner | Note |
|---|---|---|
| deployed vs distributed (Layout 06) | L1 | it defines what the repo *is* to external consumers |
| grouping topology (flat / plane-grouped / hybrid) | L2 | shapes the tree; L3 inherits its slot |
| workspace rooting (repo root vs group folder) | L2 | part of the root contract |
| package **placement** (which scope) | L2/L3 interface | rule: lowest level containing all consumers |
| package **internals** (export surface, skeleton) | L3 | |
| DB **engine** choice + provisioning | L2 | infra is repo-level |
| DB **usage** conventions per app | L3 | |
| migration style + DDL owner | L3 | escalates to L2 when two backends share one DB (`two-plane-split.md`) |

## The five principles — stated once, instantiated per level

1. **Skeleton firm, contents vary.** Every container promises a hard skeleton at its top level; below it, project-specific. L2: root inventory. L3: `src/` layers, `app/` domains. L4: `{router,service,repository,models}.py`, `layout/<shell>/`.
2. **Flat until a threshold, then group.** Grouping layers are earned by count or by a settled model — never pre-created, never skipped past the tripwire. L2: `apps/` planes. L3: backend domains. L4: feature-folder subdivision.
3. **Code lives at the lowest level that contains all its consumers.** L2: package scope (client group vs root `packages/`). L3: domain-shared vs `core/`. L4: feature-internal types vs `api/` vs `packages/types`.
4. **The root is an index, not a runtime.** Roots orchestrate and link inward; runtimes live inside folders. L2: repo root (`root-and-hygiene.md`). L3: a package's `index.ts` export surface. L4: thin `pages/` routing into `features/`.
5. **Structure is versioned and re-openable.** Chosen variants + tripwire numbers are recorded in CLAUDE.md; when the model settles or a number trips, structure reconciles. All levels.

When a situation has no written rule, resolve it from these principles at the right altitude — then record the resolution.

## Master tripwire table

Structure gets numbers, like the file caps — checkable while working, not vibes. Crossing one obligates **either the restructure or a recorded deferral** (one line in CLAUDE.md: what, why, until when). Silent crossing is the failure mode.

| # | Tripwire | Threshold | Action | Owner |
|---|---|---|---|---|
| T1 | apps in a flat `apps/` hiding planes | 2+ frontends AND (2+ backends OR frontend-only packages) | plane-grouped topology | L2 (`02_multi-app-monorepo.md`) |
| T2 | feature folders per app | ~8–10 | introduce a domain layer | L3 (`domain-grouping-tripwire.md`) |
| T3 | source files per feature folder | ~10 | subdivide the feature | L4 (`intra-app-structure.md`, backend twin in `domain-grouping-tripwire.md`) |
| T4 | components flat in a ui package | ~15 | group by component family | L3 (`intra-app-structure.md`) |
| T5 | lines per file | 500 hard / 300 soft | split | L4 (`file-size-caps.md`) |
| T6 | lines per `pages/` file | ~50 | substance moves to `features/` | L4 (`intra-app-structure.md`) |
| T7 | `ctl` dispatcher size / needs structured state | ~150 lines | escalate to a binary | L2 (`complex-setups.md`) |
| T8 | same utility combo twice (styling) | 2 | fold into a primitive variant | L4 (`styling-discipline.md`) |
| T9 | same logic three times | 3 | extract a shared helper | L4 (`extract-on-third-use.md`) |
| T10 | runtime deps in a root manifest | 1 | move it into the app/package folder | L2 (`root-and-hygiene.md`) |

## Evolution machinery — structure after bootstrap

Bootstrap-time layout is a starting point, never a contract. Four rules keep it alive:

1. **Every choice is recorded.** The CLAUDE.md carries the chosen variants (topology, rooting, BFF/core, migration owner, any sanctioned exception) and the tripwire numbers. **Audits compare the repo against its *recorded* choices** — an unusual shape with a recorded choice is a variant; a missing record is the finding.
2. **Reconcile when the model settles.** When the product's domain model / IA is decided or meaningfully revised, code structure reconciles **within the same milestone** — not deferred indefinitely.
3. **Restructures ride consolidation windows.** Folder moves and renames batch into windows where churn already happens (schema consolidation, major refactor, pre-release reset) — import churn is paid once, not per-PR.
4. **Audits get triggers.** Run `/ps-setup audit` at roadmap-stage boundaries and whenever a tripwire is crossed — not "someday".

## Escalation — when the standard runs out

If a structural decision falls outside the recorded standard, or the standard itself seems wrong: load the `project-setup` skill and resolve it at the right level — **never improvise a new pattern inline**. The CLAUDE.md blocks are the always-loaded summary; this skill is the authority they defer to. That escalation pointer ships inside the CLAUDE.md template so every future agent knows who to ask.

## See also

- `references/levels/01_ecosystem.md` · `02_repo.md` · `03_app.md` · `04_feature.md` — the per-level charters
- `references/00_decision-tree.md` — the L2 layout picker
- `references/01_question-flow.md` — the level-ordered question flow
