# Project-setup guide amendments — intra-app structure doctrine

> **STATUS: IMPLEMENTED — v2 (0.2.0), 2026-07-17.** All amendments below landed
> as part of the plugin's v2 restructure around a four-level altitude model,
> plus additional scope decided in follow-up discussion. This document remains
> as the historical work order; the plugin content itself is project-agnostic
> and forward-looking (no case-study narrative was carried into the skill).
> Where each amendment now lives:
>
> - **Spine (new in v2)** — `references/levels/00_altitude-model.md` (4 levels,
>   5 principles, master tripwire table, evolution machinery) + per-level
>   charters `references/levels/01–04_*.md`; question flow rewritten
>   level-ordered; SKILL.md routes by altitude.
> - **Amendment A** → `references/architecture/modularity/domain-grouping-tripwire.md`
>   (tripwire, naming, feature seams, adapter-modules, DTO placement; generic
>   worked example) + ceiling note in `folders-by-feature.md`.
> - **Amendment A2** → `references/architecture/backend/two-plane-split.md`
>   (+ identity-plane question in `01_question-flow.md`; cross-links from both
>   alembic references).
> - **Amendments B + B2** → `references/architecture/frontend/intra-app-structure.md`
>   (src/ skeleton, api-layer doctrine, type placement, pages/features,
>   subdivision tripwire, package internals); `single-frontend.md` aligned.
> - **Amendment C** → evolution machinery in `levels/00_altitude-model.md`;
>   CLAUDE.md.template gained the "Structure contract" block (recorded variant
>   choices + tripwires + escalation pointer); audit mode counts tripwires and
>   compares against recorded choices (SKILL.md + ps-setup.md).
> - **Beyond this doc (v2 scope)** — grouping-topology variants + core-vs-BFF
>   axis (`02_multi-app-monorepo.md`), root-as-index + workspace rooting +
>   gitignore doctrine (`repo-setup/root-and-hygiene.md` + gitignore snippet),
>   ctl conformance floor (`runtime/script-overview.md`), L1 ecosystem charter
>   (docs placement, repo-split criteria), examples index converted to a
>   per-installation registry (plugin ships project-agnostic).
> - **Checklist correction**: the final item below assumed the question flow
>   needed no change — v2 did change it (identity plane, topology, rooting,
>   docs placement, migration style are now asked).

Instruction document for the agent maintaining the `project-setup` plugin
(skills/project-setup). Written 2026-07-17, extracted from a structural
post-mortem of the `anitrack` repo. The goal: amend the guide so that the
class of failure described below cannot recur in any project bootstrapped
or audited by the plugin.

How to use this document: treat every "Amendment" section as a work order.
Each names the reference files to create or edit, the doctrine to encode,
and a worked example. The case study is context — read it first so the
amendments land as fixes to a real failure, not abstract preferences.

---

## 1 · Case study — what went wrong in anitrack

A multi-app monorepo (2 FastAPI backends, 2 Vite/React frontends in a bun
workspace, layout 02). All plugin conventions were followed faithfully.
Structure still degraded, in both planes:

**Backend.** `apps/api-admin/app/` accumulated 17 flat feature folders
(`audit, catalog, core, dashboard, graph, grouping, images, invites, jobs,
nomenclature, operators, scrape, security, sources, system_settings,
users, …`). Two of them (`sources/`, `scrape/`) are actually one feature —
one lifecycle (a source and its runs) — awkwardly split in two. The product meanwhile settled a clear domain model
(catalog-building, exploration, access, system) that the folder tree does
not reflect. Finding "everything about the catalog pipeline" means opening
four unrelated top-level folders.

**Frontend.** `apps/client/admin/src/features/sources/` grew into a single
flat pile of ~30 files — pages, dialogs, sections, editors, and their
tests all siblings. There is no `pages/` layer (routes in `App.tsx` import
feature files directly), no `api/` layer (fetch logic lives inside
features), no `hooks/`, no `layout/`.

**Root cause analysis — three findings:**

1. **The guide's resolution stops at the single feature folder.** The
   modularity references cover folders-by-feature, rule-of-three, and
   file-size caps. Nothing addresses the layer above the feature folder
   (backend domains) or below it (frontend feature subdivision). The gap
   is in the convention, not in compliance.
2. **There is a threshold rule for files but none for structure.** A file
   that crosses 500 lines must split — that tripwire works because it is
   a number an agent can check. No equivalent exists for "this app has too
   many flat folders" or "this feature folder has too many flat files", so
   growth never triggered action.
3. **Conventions freeze the bootstrap-time snapshot and nothing re-opens
   them.** At bootstrap there were 5–6 features; flat was correct. The
   product's domain model settled much later, and no mechanism (no
   tripwire in CLAUDE.md, no scheduled audit) prompted reconciliation.
   Every agent behaved locally correctly — follow the existing pattern,
   add a folder — while the global structure drifted.

---

## 2 · Amendment A — backend domain layer (new reference)

Create `references/architecture/modularity/domain-grouping-tripwire.md`
(and cross-link it from `folders-by-feature.md` and the backend
references). Encode:

### The tripwire

When an app crosses **~8–10 feature folders**, or when the product's
domain model settles (whichever comes first), introduce a **domain
layer**: `app/<domain>/<feature>/…`. Below the threshold, stay flat —
the flat default remains correct for small apps.

To be unambiguous: the driver is **feature cohesion** — collating
backend features that own one body of data and change together. It is
NOT "mirror the sidebar" or any UI navigation structure. UI IA is at
most a hint that a domain model exists; the grouping itself is derived
from what the code owns, and it is legitimate for the backend grouping
and the UI grouping to differ (in the worked example below they do:
the UI shows Build and Catalog as separate nav groups, the backend has
one `catalog` domain).

### Domain naming rules

- Domains are named by **nouns of ownership** (what the code owns:
  `catalog`, `access`), never by activities (`build`, `sync`) and never
  by copying UI navigation labels.
- Backend groups by **domain**; the UI groups by **workflow**. These
  correlate but must not be forced 1:1 — nav IA churns cheaply, package
  moves churn expensively. The mapping between the two is a documented
  decision, not an implicit mirror.
- Cross-cutting infrastructure (db, settings, security plumbing, health)
  stays in `core/` — never force-fit a genuinely shared feature into a
  domain, because a wrong placement is a standing lie.
- Ambiguous placements (a `dashboard` that aggregates everything, an
  `images` feature serving two domains) get an explicit one-line rationale
  recorded next to the structure (in the project CLAUDE.md or a
  `structure.md`), so the next agent inherits the decision instead of
  re-litigating it.

### Mechanics

- Each domain gets an **aggregator router** (`app/<domain>/router.py`)
  mounting its features' routers; the app entrypoint mounts one router
  per domain. Feature folders keep the standard
  `{router,service,repository,models}.py` shape unchanged.
- Domain-shared machinery (e.g. a cycle-ledger helper used by several
  features of one domain) lives at the domain root, not in global `core/`.

### Feature seams — grouping never fixes a wrong split

A domain layer organizes features; it does not repair badly drawn
feature boundaries, and the guide must say both things:

- **A feature boundary follows lifecycle and ownership, not pipeline
  stage or activity.** Two folders that own one body of data and one
  lifecycle are ONE feature and must be merged, not merely grouped
  under the same domain. In the case study, `sources/` (the registry)
  and `scrape/` (the runs) were one lifecycle split in two — putting
  both inside `catalog/` would have hidden the wrong seam, not fixed
  it; the correct move was a single `catalog/sources/` feature owning
  registry, configs, runs, and trace.
- Symptom to check for in audits: two feature folders that are always
  edited together, share vocabulary, or expose one UI surface.

### The adapter-modules pattern (integrating N external providers)

When one feature integrates several external sources/providers of the
same kind (data sources, payment gateways, notification channels),
encode this shape:

```
<feature>/
  structure.py        # the ONE canonical output/contract shape all adapters map to
  cycles.py …         # generic engine code — never provider-specific
  modules/
    base.py           # the adapter contract every provider implements
    <provider_a>/     # self-contained: fetch.py, transformer.py, config.py, …
    <provider_b>/
```

Rules: engine code stays generic and reads adapters only through
`base.py`; each provider folder is self-contained (its acquisition,
its mapping to the canonical shape, its defaults — all versioned
together); adding a provider = adding one folder, touching nothing
else. Provider-specific logic leaking into engine files is the drift
symptom audits should flag. The backend feature-folder file count has
the same ~10-file subdivision tripwire as the frontend — `modules/`
(and, when needed, an `engine/` sub-folder) is how a large feature
subdivides without breaking the one-feature-one-folder rule.

### Type and DTO placement (make this explicit — it is load-bearing)

The guide must state where API contract types live, not leave it
implied. For a Python/FastAPI backend:

- **`models.py` in each feature folder holds the Pydantic DTOs** — the
  request and response models that define that feature's API contract.
  This is the existing `{router,service,repository,models}.py` shape;
  the amendment is to say it out loud: `models.py` means *API contract
  models*, and in a raw-SQL project it never means ORM models (there are
  none — the database schema is the contract, owned by migrations).
- Validation and serialization live on these DTOs (Pydantic validators,
  field constraints), so the contract is enforced where it is declared.
- Enums / value objects / config-shape models shared by several features
  of one domain live at the **domain root** (e.g. `catalog/models.py` or
  `catalog/types.py`); shared by the whole app → `core/`. Never import
  DTOs across domains to "reuse a shape" — duplicate the shape instead;
  cross-domain imports of contract models create hidden coupling that
  outlives the convenience.
- Two backends never share a models package; each owns its contract
  (the database schema is the only shared contract between them).

### Worked example (anitrack target shape)

```
app/
  core/        # db, settings, security plumbing, health
  catalog/     # sources, source_cycles, ingestion, analysis, images, nomenclature
  explore/     # graph visualization / curation surface
  access/      # users, operators, invites, security
  system/      # system_settings, jobs, storage, audit, dashboard
```

Note `catalog` — the pipeline that *builds* the catalog and the catalog
itself are one domain (the pipeline's entire output is the catalog); an
earlier draft named the group `build` and was rejected for being an
activity name. This is exactly the judgment the naming rules encode.

---

## 2b · Amendment A2 — the admin/user two-plane split (decision guidance)

The question flow asks "how many backends? how many frontends?" as bare
counts and the references document the *mechanics* of an admin+user pair
(workspace packages, nginx routing, env isolation) — but nothing tells an
agent or user **when the split is the right answer**. Encode the decision:

- **Split admin (operator) and user (platform) into separate backends
  when they need different security postures**: a separate operator
  identity namespace (own credentials table, own session/refresh
  namespace, no third-party OAuth, bootstrap via a break-glass CLI rather
  than signup), independent exposure (admin can stay off the public edge
  / on an internal network), or independent deploy cadence. Any one of
  these is sufficient; a styling difference or a nav difference is NOT —
  that's one backend with role-gated routes.
- **One database is the normal case, not a smell.** Two backends over one
  Postgres works when ownership is strict: every fact kind has exactly
  one writing owner, the schema (owned by a single migrations app that
  imports neither backend) is the only shared contract, and there is no
  shared ORM/models package between the backends — each declares its own
  DTOs against the schema.
- **Frontends of the two planes share a workspace** and its packages (ui,
  tokens/styles, types, auth services) — the visual language is shared
  even when the identity planes are not. Backend secrets never enter
  either frontend's env scope (existing rule; cross-reference it).
- **Migrations get a neutral owner: a standalone `apps/db` app.** The
  existing anti-pattern rule ("two DDL owners — pick one; the rest
  consume") is right but under-specified: with two backends over one
  database, the owner should be NEITHER of them. A standalone migrations
  app (Alembic + the raw-SQL three-file pattern) that imports no backend
  code is the sole DDL owner; both backends are pure consumers of the
  schema contract; it runs only via the dispatcher (`ctl migrate
  up|down|new|status`), never on app boot. Making one backend the owner
  creates a false hierarchy (the "owning" backend looks authoritative
  over shared tables) and couples schema changes to that app's deploy
  cadence. The entrypoint-migrates default remains correct for the
  single-backend case; document this as the two-backend escalation.
- Add one question to the question flow: not just "how many backends?"
  but "does any surface need a separate identity/security plane
  (operator/admin vs end-user)?" — the count falls out of the answer,
  instead of being guessed.

## 3 · Amendment B — frontend intra-app structure (new reference)

The guide currently has no reference for the structure *inside* a
frontend's `src/` (the frontend references cover workspace placement,
env isolation, shared packages — nothing below `src/`). Create
`references/architecture/frontend/intra-app-structure.md`. Encode the
following canonical layout:

```
src/
  layout/      # app shells / structural layouts (sidebar+topbar frames, auth frame)
  components/  # common composed components (navbar, page header, empty states)
  features/    # per-domain feature code — subdivided, see rules below
  pages/       # thin route components mirroring the URL tree; import from features/
  hooks/       # shared hooks
  api/         # THE api access layer — see doctrine below
  lib/         # pure utilities
  stores/      # client state (zustand or equivalent)
  styles/      # only if no workspace styles package exists
tests/         # cross-cutting test setup (unit tests co-locate with source)
public/
```

### Workspace reconciliation rule

In a multi-frontend workspace, three of these layers usually graduate to
packages and must NOT be duplicated locally: primitive UI elements
(buttons, tables, inputs) → `packages/ui`; design tokens/styles →
`packages/styles`; auth/session services shared across apps →
`packages/services`. The reference must state both variants explicitly
(standalone app: local folders; workspace: packages) so agents don't
create a local `elements/` beside an existing `packages/ui`.

### The api-layer doctrine

No component, hook, or store calls `fetch`/axios directly. All server
communication goes through functions in `api/` (or a `packages/services`
equivalent), which own: endpoint paths, request/response typing (zod
parsing at the boundary), error normalization into one shape, and the
query-key vocabulary for the data-fetching library (TanStack Query keys
live beside the functions they cache). This is the single place the
backend contract is expressed; when the API changes, the diff is
localized here plus the affected features.

### Type placement (frontend)

State explicitly where every kind of type lives; untyped-boundary drift
starts exactly where this is left implicit:

- **API request/response types live in `api/`, beside the functions
  that use them.** The zod schemas parsing responses at the boundary are
  the source of truth; the TS types are inferred from them
  (`z.infer<…>`) — never hand-written twins that can drift. When the
  backend contract changes, `api/` is the single place the type diff
  appears.
- **Cross-app shared types** (entities used by both a platform and an
  admin client) → the workspace `packages/types`; an app-local `api/`
  may re-export from it but never redefines it.
- **Feature-internal types** (view models, component state shapes)
  co-locate inside the feature folder — they are implementation detail,
  not contract, and must not leak into `api/` or packages.
- **Store state types** live with the store definition; **component prop
  types** live in the component file. No global `types.ts` dumping
  ground — a type without an owner is a type nobody updates.

### pages/ vs features/ split

`pages/` files are thin: route wiring, param parsing, composition of
feature components — target under ~50 lines each, and the folder tree
mirrors the URL structure. All substance lives in `features/`. Routes in
the router config import pages, never feature internals.

### The feature-folder subdivision tripwire

Same threshold logic as the backend: when a feature folder crosses
**~10 source files**, subdivide — either by sub-feature
(`features/sources/configs/`, `features/sources/runs/`) or by kind within
the feature (`pages/`, `dialogs/`, `sections/`) — whichever axis carries
the real seams. Tests co-locate with what they test through the split.
A 30-file flat feature folder is the frontend twin of the 17-folder flat
backend and must trip the same reflex.

---

## 3b · Amendment B2 — packages get the same discipline

Workspace packages (`packages/ui`, `packages/services`, `packages/types`,
…) are currently structural dark matter: the guide says *when* to create
them but nothing about their inside. Encode (in the intra-app-structure
reference or a short sibling):

- A package has the same two-level promise as an app: a hard skeleton at
  the top, features/groups below it. For a UI package:
  `src/<component-group>/` (or flat `src/<component>.tsx` below ~15
  components, subdividing past that — same tripwire logic); for a
  services/types package: one folder per domain area, mirroring the
  owning backend domain names where a mapping exists.
- **One export surface**: everything public goes through the package's
  `index.ts` (or documented sub-path exports); consumers never deep-import
  internal paths. The export file IS the package's contract — reviewable
  in one screen.
- The same thresholds apply (files-per-folder, lines-per-file); packages
  do not get an exemption just because they are "shared code" — they are
  read by more people, so navigability matters more, not less.

## 4 · Amendment C — evolution machinery (the meta-fix)

The deepest failure was not a missing layout — it was that **structure
had no numbers attached and no re-opening mechanism**. Encode in the
guide (a short new reference, plus template updates):

1. **Every structural convention ships with a threshold.** Like the
   500-line file cap: features-per-app (~8–10), files-per-feature-folder
   (~10), routes-per-router — concrete numbers an agent can check while
   working, not vibes. Crossing one obligates either the restructure or
   an explicit recorded deferral.
2. **The CLAUDE.md structure contract — replicate the styling-discipline
   mechanism.** The plugin already solves exactly this problem once: the
   styling discipline ships as a mandatory CLAUDE.md block (summary +
   hard rules + precedence statement), with the skill as the deep
   reference behind it. Extend the same two-layer mechanism to structure.
   Update `assets/snippets/claude/CLAUDE.md.template` with a "Code
   structure" block that carries:
   - a **summary of the project's actual structure standard** — the real
     top-level skeleton (domains/apps/packages, resolved to this
     project's names), the feature-folder shape, where types/DTOs live;
   - the **tripwire numbers** (features-per-app, files-per-feature,
     lines-per-file) as checkable rules;
   - an explicit **escalation pointer**: "if a structural decision falls
     outside this summary, or the standard itself seems wrong or needs
     updating, load the `project-setup` skill and follow its guidance —
     do not improvise a new pattern inline." CLAUDE.md is the
     always-loaded summary; the skill is the authority it defers to.
   Rationale: skills load sometimes; CLAUDE.md loads always — a
   convention that isn't in CLAUDE.md does not exist for the average
   working agent, and a CLAUDE.md that can't say "who to ask" invites
   improvisation exactly when the standard runs out.
3. **Structure reconciles when the domain model settles.** New doctrine
   line: when a product's IA/domain model is decided (or meaningfully
   revised), the code structure must be reconciled within the same
   milestone — not deferred indefinitely. Bootstrap-time layout is a
   starting point, never a contract.
4. **Restructures ride consolidation windows.** Folder moves and renames
   are batched into windows where churn is already happening (a schema
   consolidation, a major refactor, a pre-release reset) so import-churn
   is paid once. The guide should name this pattern explicitly.
5. **Audits get triggers.** `/ps-setup audit` exists but was never run.
   Recommend concrete trigger points in the guide: at each roadmap-stage
   boundary, and whenever a tripwire number is crossed.

---

## 5 · Deliverables checklist for the guide agent

- [ ] New: `references/architecture/modularity/domain-grouping-tripwire.md` (Amendment A — including the type/DTO placement section, the explicit "cohesion, not UI navigation" framing, the feature-seams rule, and the adapter-modules pattern)
- [ ] New: `references/architecture/frontend/intra-app-structure.md` (Amendment B — including the frontend type-placement section)
- [ ] New or folded into Amendment B's reference: package-internal structure conventions (Amendment B2 — skeleton, one export surface, same tripwires)
- [ ] New: two-plane split decision guidance (Amendment A2 — when admin/user get separate backends, one-DB ownership rules, shared frontend workspace, the standalone `apps/db` migrations owner) + the added identity-plane question in `01_question-flow.md`; cross-link from the alembic references ("two backends? the owner is a standalone db app — see A2")
- [ ] New or folded into an existing modularity file: evolution machinery / tripwire doctrine (Amendment C)
- [ ] Edit: `folders-by-feature.md` — add a closing section pointing at the domain layer ("this rule has a ceiling; see domain-grouping-tripwire")
- [ ] Edit: `assets/snippets/claude/CLAUDE.md.template` — add the "Code structure" block: project-resolved skeleton summary, tripwire numbers, reconcile-on-IA-settle, restructures ride consolidation windows, and the escalation pointer to the `project-setup` skill (mirror the styling-discipline block's shape and precedence language)
- [ ] Edit: audit-mode instructions in the skill — audit must count features-per-app and files-per-feature-folder and flag threshold crossings as findings
- [ ] Edit: the skill's file map — index the two new references with one-line comments matching their decision surface
- [ ] Verify: the question flow / decision tree needs no change (these amendments are post-bootstrap doctrine, not bootstrap questions) — confirm and note it
