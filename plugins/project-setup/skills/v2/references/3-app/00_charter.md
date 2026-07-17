# L3 — App: inside one app or package

The internal structure of each runnable app and each workspace package: its skeleton, how features group, where shared code and contracts live, how its data layer is owned and served. Binds when the app is created — mostly derived from L2's decisions plus a few per-app questions — and is recorded in the CLAUDE.md structure block. Inherits its slot from L2; hands folder-level contracts down to L4. This charter is an **index of L3 decisions → their owner files**; it never restates a rule.

## Decisions owned here

| Decision | Rule / default | Owner |
|---|---|---|
| **Backend skeleton** | Flat `app/` (run-service, no `src/`): `main.py` + `core/` + feature folders; `src/<pkg>/` only for distributables. Includes the `pyproject.toml` + `uv sync` flow. | `references/3-app/backend/app-skeleton.md` |
| **Backend domain layer** | Flat until tripwire T2 or the domain model settles → `app/<domain>/<feature>/` with aggregator routers. Domains named by ownership nouns, never activities or nav labels. | `references/3-app/backend/domain-grouping.md` |
| **Migration style + owner** | Plain Alembic (autogenerate + review) default; raw-SQL three-file pattern when non-Python consumers read the schema; two backends over one DB → neutral `apps/db`, `ctl migrate` only. | `references/3-app/backend/migrations.md` |
| **App-level serving** | Per-language worker model + recycling + timeouts + health endpoints. Python is the outlier needing worker-process recycling; Rust/Go/Node scale via replicas. | `references/3-app/backend/serving.md` |
| **ML Python flow** | `requirements.txt` + uvenv global env for ML projects (Layout 04) — deliberately different from the app flow. | `references/3-app/backend/ml-python-flow.md` |
| **Two-plane split** | Admin/user backends split only on security-posture grounds; then the DB moves to a neutral `apps/db`. | `references/3-app/backend/two-plane-split.md` |
| **Frontend skeleton** | The hard `src/` skeleton: `layout/ components/ features/ pages/ hooks/ api/ lib/ stores/ (styles/)`. Pages thin and URL-mirroring; all server communication through `api/`. | `references/3-app/frontend/app-skeleton.md` |
| **Workspace reconciliation** | In a workspace, `ui`/`styles`/`services` are packages — never duplicated as local folders. Both variants legitimate; never both at once. | `references/3-app/frontend/app-skeleton.md` § workspace reconciliation |
| **Shared-lib placement** | Lowest level containing all consumers: feature-internal → the feature; domain-shared → domain root; app-wide → `core/`/`lib/`; cross-app → a workspace package (scope per L2 topology). | `references/3-app/backend/domain-grouping.md`, `references/2-repo/grouping-topology.md` |
| **Package internals** | Same two-level promise as an app; ONE export surface (`index.ts` / documented sub-paths); services/types packages mirror the owning backend's domain names. | `references/3-app/frontend/shared-packages.md` |
| **Type / DTO ownership** | `models.py` = the feature's API contract; frontend types inferred from zod in `api/`; cross-app entities in `packages/types`; no cross-domain DTO imports; no shared models package between backends. | `references/4-feature/types-and-contracts.md` |
| **Per-app DB usage** | The app's engine conventions — connection ownership, key naming, extension use — per engine (engine *choice* is L2). | `references/3-app/database-usage/{postgres,redis,sqlite,other-engines}.md` |
| **Embeddable seams** | Embedding seams / IoC config API / per-instance mounts (repo shape + publishing stay at L2 Layout 06). | `references/3-app/frontend/embeddable-seams.md` |

## Invariants (firm at this level)

- Every app/package owns its **manifest, `config.yaml` (backends), README, Dockerfile** — no sharing, no symlinks.
- **Skeleton names are firm** at the top level of `app/` and `src/`; contents below vary by project.
- **The api layer is the only server-communication surface** in a frontend.
- **Contracts have one owner each** — a schema, a DTO, an exported type each live in exactly one place.

## Per-app questions (the few not derivable from L2)

1. Migration style — autogenerate vs raw-SQL (driven by: non-Python schema consumers? hand-tuned DDL? review requirements?). See `references/3-app/backend/migrations.md`.
2. Client-state library (zustand default) and data-fetching library (TanStack Query default) — names go into the structure block.
3. For a package: what is the export surface, and does it publish externally (then Layout 06 publishing rules apply)?

## Named variants (choices, not drift — record each in CLAUDE.md)

backend skeleton (flat `app/` / src-layout) · migration style (Alembic / raw-SQL / neutral `apps/db`) · workspace reconciliation (local folders / workspace packages) · client-state + data-fetching libraries · package export surface.

## Tripwires at this level

T2 (features → domains, `references/3-app/backend/domain-grouping.md`), T4 (ui package grouping, `references/3-app/frontend/shared-packages.md`). T3/T5/T6 live at L4 but are counted per-app during audits. Master table: `references/00_altitude-model.md`.

## Hands down to L4

Each feature folder receives its shape contract (`{router,service,repository,models}.py` / the feature's frontend subdivision axes), the type-placement rules, and the tripwire numbers — via the CLAUDE.md structure block, since L4 agents may never load this skill. See `references/4-feature/00_charter.md`.

## Audit at this level

- Count feature folders per app (T2) and files per feature (T3) → crossings without a recorded deferral = finding.
- Frontend skeleton: missing `pages/` or `api/` in a grown app; fetch outside `api/` (grep); local `ui`/`styles` duplicating workspace packages (red).
- Backend: cross-domain DTO imports; a shared models package between two backends (red); migrations on boot in a two-backend repo (red); activity-named domains; src-layout on a run-service backend.
- Packages: undocumented deep-import paths in consumers; missing export surface.
- The CLAUDE.md structure block exists and matches reality (missing = red).

## See also

- `references/00_altitude-model.md` — the 4+1 levels, master tripwire table, ownership table
- `references/2-repo/00_charter.md` (step up) · `references/4-feature/00_charter.md` (step down)
