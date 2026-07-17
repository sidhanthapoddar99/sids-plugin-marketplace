# Feature folders — the backend feature shape and its seams

The L4 backend feature: what a feature folder contains, what makes something *one* feature (and when two folders are secretly one), how a feature that integrates several external providers is shaped, and when a big feature subdivides without fragmenting. The layer above — grouping features into domains (tripwire T2, naming, aggregator routers) — is L3, owned by `references/3-app/02-backend/01_domain-grouping.md`. Where API contract types actually live is owned by `references/4-feature/03_types-and-contracts.md`.

## The feature-folder shape

One feature, one folder, four standard files:

```
<feature>/
├── router.py       # the feature's HTTP surface — endpoint definitions; mounts into the domain/app router
├── service.py      # business logic — the feature's behaviour, orchestration, rules
├── repository.py   # data access — queries and persistence for this feature's data
└── models.py       # the feature's API-contract DTOs (what lives here → types-and-contracts.md)
```

- **Feature-internal helpers stay feature-scoped.** A util used only inside this feature lives in the feature folder (its own file or a small `helpers.py`), not hoisted to `core/`. Code lives at the lowest level that contains all its consumers.
- **`models.py`** names the contract file in the shape; *what* goes in it — DTO placement, cross-domain import rules, the raw-SQL "no ORM models" case — is owned by `references/4-feature/03_types-and-contracts.md`. Don't restate those rules here.
- The shape is uniform whether the app is flat (`app/<feature>/`) or grouped (`app/<domain>/<feature>/`). Domains don't change the feature shape — see `references/3-app/02-backend/01_domain-grouping.md`.

## Feature seams — what is one feature

Grouping features into domains *organises* them; it never repairs a boundary drawn in the wrong place. The two rules are independent — a domain layer over a wrong seam just hides it.

- **A feature boundary follows lifecycle and ownership, not pipeline stage or activity.** Two folders that own **one body of data and one lifecycle** are ONE feature and must be **merged**, not merely parked under the same domain. Example: a `registry` feature and a separate `runs` feature for the same entities (a registry and its execution history — one lifecycle split in two) become a single feature owning registry, configs, runs, and trace. Splitting by pipeline stage (`ingest/` → `transform/` → `load/`) is the classic wrong seam: it slices one lifecycle across folders that must always change together.
- **Merge before you group.** Putting two half-features inside one domain without merging leaves the seam wrong. Merge, then group.
- **Audit symptom**: two feature folders that are always edited together, share vocabulary, or expose one UI surface → merge candidates.

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
- **The canonical shape (`structure.py`) is owned by the feature**, not by any provider — adapters map *to* it, never extend it ad hoc.

## Backend subdivision — the tripwire (T3)

A feature folder that keeps the four-file shape stays flat. When it crosses **~10 source files**, subdivide — but *inside* the folder, never by splitting the feature across siblings:

- `modules/` is the primary subdivision tool (as in the adapter-modules pattern above): one self-contained subfolder per provider / sub-capability.
- Add an `engine/` subfolder when the generic machinery itself grows past a file or two.
- The one-feature-one-folder invariant holds throughout: subdivision deepens the folder, it does not fragment the feature.

Crossing T3 obligates either the subdivision or a recorded deferral (one line in CLAUDE.md: what, why, until when) — silent growth is the failure mode. The **frontend twin** of T3 (subdivide a frontend feature by sub-feature or by kind) is owned by `references/4-feature/02_api-and-pages.md`.

## Audit checks

- Count source files per feature folder → **~10+ with no subdivision and no recorded deferral = finding** (T3).
- Two feature folders always co-edited, sharing vocabulary, or fronting one UI surface → wrong-seam finding (merge candidates).
- Grep the engine files of an adapter feature for provider names → leak finding.
- A feature-internal helper hoisted to `core/` with a single consumer → placement finding.

## Anti-patterns

- Splitting one feature by pipeline stage (`ingest/`/`transform/`/`load/`) — that slices one lifecycle; keep it one feature.
- Grouping two folders that are one feature under a domain instead of merging them — the seam stays wrong.
- Provider-specific `if source == "x"` branches in engine code — route through `base.py`.
- Adapters extending the canonical shape ad hoc instead of mapping to it.
- A 15-file feature left flat — subdivide with `modules/`, don't scatter it across sibling folders.

## See also

- `references/3-app/02-backend/01_domain-grouping.md` — the altitude above: grouping features into domains (T2), naming, aggregator routers, domain-shared placement
- `references/4-feature/03_types-and-contracts.md` — what lives in `models.py`; no cross-domain DTO imports; no shared models package
- `references/4-feature/02_api-and-pages.md` — the frontend twin: feature subdivision (T3), `api/` internals, thin pages (T6)
- `references/4-feature/05_caps-and-extraction.md` — file caps (T5), rule of three (T9), folders-by-feature, test co-location
- `references/4-feature/00_index.md` — the L4 charter this reference serves
