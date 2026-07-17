# Domain grouping — the layer above feature folders

`folders-by-feature.md` organises code *within* one altitude: one feature, one folder. This reference owns the altitude above it: **when an app has enough features that the flat list itself stops communicating the product, group features into domains** — `app/<domain>/<feature>/…`. It also owns the rules that keep that grouping honest: how domains are named, where shared code lands, and what a feature boundary is in the first place.

## The tripwire

Introduce a domain layer when **either** happens — whichever comes first:

- the app crosses **~8–10 top-level feature folders**, or
- the product's **domain model settles** (the team can name the 3–6 areas the product is "about").

Below the threshold, **stay flat** — a domain layer over five features is empty ceremony. Crossing the threshold obligates one of exactly two actions: restructure, or record an explicit deferral (one line in the project CLAUDE.md: what was deferred and until when). Silent growth past the tripwire is the failure mode this rule exists to prevent.

```
# below the tripwire — flat is correct          # past the tripwire — grouped by domain
app/                                            app/
├── core/                                       ├── core/          # cross-cutting plumbing (unchanged)
├── auth/                                       ├── catalog/       # domain
├── users/                                      │   ├── router.py  # aggregator router
├── catalog/                                    │   ├── sources/   # feature
├── orders/                                     │   ├── imports/   # feature
└── notifications/                              │   └── media/     # feature
                                                ├── orders/
                                                │   ├── router.py
                                                │   ├── checkout/  billing/  fulfilment/
                                                ├── access/
                                                │   ├── router.py
                                                │   ├── users/  operators/  invites/
                                                └── system/
                                                    ├── router.py
                                                    ├── jobs/  audit/  settings/
```

## What drives the grouping: cohesion, not navigation

A domain collates features that **own one body of data and change together**. It is *not* a mirror of the UI's sidebar or nav structure:

- **Backend groups by domain** (what the code owns); **the UI groups by workflow** (what the user does). These correlate but must never be forced 1:1 — nav IA churns cheaply, package moves churn expensively.
- UI structure is at most a *hint* that a domain model exists. It is legitimate — and common — for the UI to show two nav groups that map to one backend domain, or vice versa.
- The mapping between backend domains and UI groups is a **documented decision** (one table in the project CLAUDE.md or a `structure.md`), not an implicit mirror.

## Domain naming rules

- Domains are named by **nouns of ownership** — what the code owns (`catalog`, `orders`, `access`), never by activities (`build`, `sync`, `ingest`) and never by copying UI navigation labels. Test: an activity name describes what the code *does this quarter*; an ownership noun describes what it *is responsible for* permanently. A pipeline that builds a catalog belongs in `catalog/` — the pipeline's entire output *is* the catalog.
- **Cross-cutting infrastructure stays in `core/`** — db, settings, security plumbing, health. Never force-fit a genuinely shared feature into a domain: a wrong placement is a standing lie that misleads every future reader.
- **Ambiguous placements get a recorded rationale.** A `dashboard` that aggregates everything, an `images` feature serving two domains — put it somewhere defensible and record the one-line why next to the structure (project CLAUDE.md or `structure.md`), so the next agent inherits the decision instead of re-litigating it.

## Mechanics

- Each domain gets an **aggregator router** (`app/<domain>/router.py`) that mounts its features' routers; the app entrypoint mounts **one router per domain**. Adding a feature to a domain touches the domain router, not the entrypoint.
- Feature folders keep the standard shape unchanged: `{router,service,repository,models}.py`.
- **Domain-shared machinery lives at the domain root** — a helper several features of one domain use goes in `app/<domain>/`, not in global `core/`. `core/` is reserved for code shared across domains. (This is the general placement rule: code lives at the lowest level that contains all its consumers.)

## Feature seams — grouping never repairs a wrong split

A domain layer *organises* features; it does not fix badly drawn feature boundaries. Both rules apply independently:

- **A feature boundary follows lifecycle and ownership, not pipeline stage or activity.** Two folders that own one body of data and one lifecycle are ONE feature and must be **merged**, not merely grouped under the same domain. A registry feature and a separate runs feature for the same entities (the registry and its execution history — one lifecycle split in two) become a single feature owning registry, configs, runs, and trace. Putting both inside one domain without merging hides the wrong seam; it doesn't fix it.
- **Audit symptom**: two feature folders that are always edited together, share vocabulary, or expose one UI surface — merge candidates.

## The adapter-modules pattern — integrating N external providers

When one feature integrates several external providers of the same kind (data sources, payment gateways, notification channels, storage backends), use this shape:

```
<feature>/
├── router.py  service.py  repository.py      # standard feature files
├── structure.py        # the ONE canonical output/contract shape all adapters map to
├── cycles.py …         # generic engine code — never provider-specific
└── modules/
    ├── base.py         # the adapter contract every provider implements
    ├── <provider_a>/   # self-contained: fetch.py, transformer.py, config.py, …
    └── <provider_b>/
```

Rules:

- **Engine code stays generic** and reads adapters only through `base.py`. Provider-specific logic leaking into engine files is the drift symptom audits flag.
- **Each provider folder is self-contained** — its acquisition, its mapping to the canonical shape, its defaults, all versioned together. Adding a provider = adding one folder, touching nothing else.
- The canonical shape (`structure.py`) is owned by the feature, not by any provider — adapters map *to* it, never extend it ad hoc.
- Large features subdivide with the same **~10-file tripwire** as everywhere else: `modules/` (and, when needed, an `engine/` subfolder) is how a big feature subdivides *without* breaking the one-feature-one-folder rule.

## Type and DTO placement

Where API contract types live is load-bearing — state it, don't imply it. For a Python/FastAPI backend:

| Type kind | Lives in | Notes |
|---|---|---|
| Feature API contract (request/response DTOs) | `<feature>/models.py` | Pydantic models; validation + serialization live on them, so the contract is enforced where it is declared |
| Domain-shared enums / value objects / config shapes | `app/<domain>/models.py` (or `types.py`) | shared by several features of one domain |
| App-wide shared types | `app/core/` | shared across domains |

- In a **raw-SQL project**, `models.py` never means ORM models — there are none; the database schema is the contract, owned by migrations (`references/architecture/backend/alembic-with-raw-sql.md`).
- **Never import DTOs across domains to "reuse a shape" — duplicate the shape instead.** Cross-domain imports of contract models create hidden coupling that outlives the convenience.
- **Two backends never share a models package.** Each owns its contract; the database schema is the only shared contract between them (see `references/architecture/backend/two-plane-split.md`).

## Reconciling structure when the domain model settles

Bootstrap-time layout is a starting point, never a contract. When the product's domain model is decided or meaningfully revised, **reconcile the code structure within the same milestone** — don't defer indefinitely. Batch folder moves and renames into **consolidation windows** where churn is already happening (a schema consolidation, a major refactor, a pre-release reset), so import churn is paid once.

## Audit checks

- Count top-level feature folders per app → **~8–10+ with no domain layer and no recorded deferral = finding.**
- Look for always-co-edited folder pairs sharing vocabulary → wrong-seam finding (merge candidates).
- Grep engine files of adapter features for provider names → leak finding.
- Domain names that are activities (`build/`, `sync/`) → naming finding.
- Ambiguous placements (`dashboard`, shared `images`) with no recorded rationale → documentation finding.

## Anti-patterns

- A domain layer over 4 features — grouping below the tripwire is ceremony, not structure.
- Domains copied from the UI sidebar — nav churns cheaply; packages don't.
- An activity-named domain (`build/`, `ingestion/`) — name what the code *owns*.
- Grouping two folders that are one feature — merge first, then group.
- A domain-shared helper parked in global `core/` — placement follows consumers.
- Cross-domain DTO imports — duplicate the shape; keep contracts independent.
- Restructuring one folder at a time across many PRs — ride a consolidation window.

## See also

- `references/architecture/modularity/folders-by-feature.md` — the altitude below: one feature, one folder
- `references/architecture/modularity/file-size-caps.md` — the altitude below that: 500/300 line caps
- `references/architecture/frontend/intra-app-structure.md` — the frontend twin (skeleton + feature subdivision)
- `references/architecture/backend/two-plane-split.md` — when domains outgrow one backend entirely
- `references/levels/03_app.md` — the app-level charter this reference serves
