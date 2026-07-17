# L3 — App: inside one app or package

The internal structure of each runnable app and each workspace package: its skeleton, how features group, where shared code and contracts live, how its data layer is owned. Binds when the app is created — mostly derived from L2's decisions plus a few per-app questions — and is recorded in the CLAUDE.md structure block. Hands folder-level contracts down to L4.

## Decisions owned here

| Decision | Rule / default | Reference |
|---|---|---|
| **Backend skeleton** | Flat `app/` (run-service, no `src/`): `main.py` + `core/` + feature folders. Feature folders keep `{router,service,repository,models}.py`. | `architecture/backend/pyproject-uv-sync-for-apps.md`, `modularity/folders-by-feature.md` |
| **Backend domain layer** | Flat until tripwire T2 (~8–10 features) or the domain model settles → `app/<domain>/<feature>/` with aggregator routers. Domains named by ownership nouns, never activities or nav labels. | `modularity/domain-grouping-tripwire.md` |
| **Migration style + owner** | Plain Alembic (autogenerate + review) for Python-only, single backend, entrypoint-migrates. Raw-SQL three-file pattern when non-Python consumers read the schema, DDL is hand-tuned, or reviewability demands SQL. **Two backends over one DB → neither owns it: standalone `apps/db`, `ctl migrate` only.** | `backend/alembic-default.md`, `alembic-with-raw-sql.md`, `when-not-alembic.md`, `two-plane-split.md` |
| **Frontend skeleton** | The hard `src/` skeleton: `layout/ components/ features/ pages/ hooks/ api/ lib/ stores/ (styles/)`. Pages thin and URL-mirroring; all server communication through `api/`. | `frontend/intra-app-structure.md`, `single-frontend.md` |
| **Workspace reconciliation** | In a workspace, `ui`/`styles`/`services` are packages — never duplicated as local folders. Both variants legitimate; never both at once. | `intra-app-structure.md` § workspace reconciliation |
| **Shared-lib placement** | Lowest level containing all consumers: feature-internal → the feature; domain-shared → domain root; app-wide → `core//lib/`; cross-app → a workspace package (scope per L2 topology). | `domain-grouping-tripwire.md`, `layouts/02` § topology |
| **Package internals** | Same two-level promise as an app; ONE export surface (`index.ts` / documented sub-paths); services/types packages mirror the owning backend's domain names. | `intra-app-structure.md` § package internals |
| **Type / DTO ownership** | `models.py` = the feature's API contract (raw-SQL projects: never ORM); frontend API types inferred from zod in `api/`; cross-app entities in `packages/types`; no cross-domain DTO imports; no shared models package between backends. | `domain-grouping-tripwire.md` § DTO placement, `intra-app-structure.md` § type placement |
| **Per-app DB usage** | The app's engine conventions — connection ownership, key naming, extension use — per engine. | `architecture/database/{postgres,redis,sqlite,mongodb-neo4j-seaweed}-…` |
| **App-level serving** | Worker model + recycling for its language; health endpoints. | `architecture/production/app-server-and-workers.md` |

## Invariants (firm at this level)

- Every app/package owns its **manifest, `config.yaml` (backends), README, Dockerfile** — no sharing, no symlinks.
- **Skeleton names are firm** at the top level of `app/` and `src/`; contents below vary by project.
- **The api layer is the only server-communication surface** in a frontend.
- **Contracts have one owner each** — a schema, a DTO, an exported type each live in exactly one place.

## Per-app questions (the few not derivable from L2)

1. Migration style — autogenerate vs raw-SQL (driven by: non-Python schema consumers? hand-tuned DDL? review requirements?).
2. Client-state library (zustand default) and data-fetching library (TanStack Query default) — names go into the structure block.
3. For a package: what is the export surface, and does it publish externally (then Layout 06 publishing rules apply)?

## Tripwires at this level

T2 (features → domains), T4 (ui package grouping); T3/T5/T6 live at L4 but are counted per-app during audits. Master table: `levels/00_altitude-model.md`.

## Hands down to L4

Each feature folder receives its shape contract (`{router,service,repository,models}.py` / the feature's frontend subdivision axes), the type-placement rules, and the tripwire numbers — via the CLAUDE.md structure block, since L4 agents may never load this skill.

## Audit at this level

- Count feature folders per app (T2) and files per feature (T3) → crossings without a recorded deferral = finding.
- Frontend skeleton: missing `pages/` or `api/` in a grown app; fetch outside `api/` (grep); local `ui`/`styles` duplicating workspace packages (red).
- Backend: cross-domain DTO imports; a shared models package between two backends (red); migrations on boot in a two-backend repo (red); activity-named domains.
- Packages: undocumented deep-import paths in consumers; missing export surface.
- The CLAUDE.md structure block exists and matches reality (missing = red).
