# Domain grouping — the layer above feature folders

When a backend app has enough features that the flat list stops communicating the product, group features into **domains** — `app/<domain>/<feature>/…`. This file owns that L3 decision: the tripwire that triggers it, how domains are named, how domain aggregator routers wire up, where domain-shared code lands, and how the structure reconciles when the model settles. What a feature boundary *is*, the feature-folder shape, and type/DTO placement are L4 — owned elsewhere and linked below.

## The tripwire (T2)

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

## Mechanics — routers and domain-shared placement

- Each domain gets an **aggregator router** (`app/<domain>/router.py`) that mounts its features' routers; the app entrypoint mounts **one router per domain**. Adding a feature to a domain touches the domain router, not the entrypoint.
- Feature folders keep the standard `{router,service,repository,models}.py` shape — owned by `references/4-feature/feature-folders.md`.
- **Domain-shared machinery lives at the domain root** — a helper several features of one domain use goes in `app/<domain>/`, not in global `core/`. `core/` is reserved for code shared across domains. This is the general placement rule: code lives at the lowest level that contains all its consumers.

## What lives one level down (L4)

Grouping *organises* features; it does not define them. These are owned by the feature level:

- **Feature seams** — what a feature boundary is (lifecycle + ownership), the merge rule for two folders that are one feature, and the backend subdivision tripwire (T3): `references/4-feature/feature-folders.md`.
- **The adapter-modules pattern** — integrating N external providers of one kind (`modules/`, `base.py`, self-contained provider folders): `references/4-feature/feature-folders.md`.
- **Type & DTO placement** — where API contract types live, no cross-domain DTO imports, no shared models package: `references/4-feature/types-and-contracts.md`.

A domain layer never repairs a wrong feature split — merge the seam first (see feature-folders), then group.

## Reconciling structure when the domain model settles

Bootstrap-time layout is a starting point, never a contract. When the product's domain model is decided or meaningfully revised, **reconcile the code structure within the same milestone** — don't defer indefinitely. Batch folder moves and renames into **consolidation windows** where churn is already happening (a schema consolidation, a major refactor, a pre-release reset), so import churn is paid once.

## Audit checks

- Count top-level feature folders per app → **~8–10+ with no domain layer and no recorded deferral = finding** (T2).
- Domain names that are activities (`build/`, `sync/`) → naming finding.
- Ambiguous placements (`dashboard`, shared `images`) with no recorded rationale → documentation finding.
- A domain-shared helper parked in global `core/` → placement finding.
- Restructuring one folder at a time across many PRs instead of riding a consolidation window → process finding.

## Anti-patterns

- A domain layer over 4 features — grouping below the tripwire is ceremony, not structure.
- Domains copied from the UI sidebar — nav churns cheaply; packages don't.
- An activity-named domain (`build/`, `ingestion/`) — name what the code *owns*.
- A domain-shared helper parked in global `core/` — placement follows consumers.
- Restructuring one folder at a time across many PRs — ride a consolidation window.

## See also

- `references/4-feature/feature-folders.md` — the altitude below: feature shape, feature seams, merge rule, adapter modules, T3
- `references/4-feature/types-and-contracts.md` — type/DTO placement for both planes
- `references/4-feature/caps-and-extraction.md` — folders-by-feature and the 500/300 line caps (T5)
- `references/3-app/frontend/app-skeleton.md` — the frontend twin (skeleton + feature subdivision)
- `references/3-app/backend/two-plane-split.md` — when domains outgrow one backend entirely
- `references/3-app/00_charter.md` — the app-level charter this reference serves
