# Type & DTO placement — both planes

Where every kind of type and DTO lives — backend and frontend. Untyped-boundary drift starts exactly where placement is left implicit, so this file states it for both planes and owns the invariants that keep contract types honest: no cross-domain DTO imports, no shared models package across backends, no global dumping ground, no hand-written twins of inferred types.

This file owns *placement*. The mechanisms that produce these types are owned elsewhere and linked: the zod parse-at-boundary and the api layer by `references/4-feature/api-and-pages.md`; the `{router,service,repository,models}.py` feature shape by `references/4-feature/feature-folders.md`; the domain / `core/` altitude by `references/3-app/backend/domain-grouping.md`; the DB-schema-as-contract by `references/3-app/backend/migrations.md`.

## Backend (Python / FastAPI)

| Type kind | Lives in | Rule |
|---|---|---|
| Feature API contract (request/response DTOs) | `<feature>/models.py` | Pydantic models; validation + serialization live on them, so the contract is enforced where it is declared |
| Domain-shared enums / value objects / config shapes | `app/<domain>/models.py` (or `types.py`) | shared by several features of one domain |
| App-wide shared types | `app/core/` | shared across domains |

- **Placement follows consumers** — a type shared by several features of one domain lives at the domain root, not in global `core/`; `core/` is reserved for types shared *across* domains. (Principle 3, instantiated for types.)
- **Never import DTOs across domains to "reuse a shape" — duplicate the shape instead.** Cross-domain imports of contract models create hidden coupling that outlives the convenience.
- **Two backends never share a models package.** Each owns its contract; the database schema is the only shared contract between them — see `references/3-app/backend/two-plane-split.md`.
- In a **raw-SQL project**, `models.py` never means ORM models — there are none; the database schema is the contract, owned by migrations (`references/3-app/backend/migrations.md`).

## Frontend (Vite / React)

| Type kind | Lives in | Rule |
|---|---|---|
| API request/response types | `api/`, beside the functions | inferred from zod schemas (`z.infer<…>`) — never hand-written twins that can drift |
| Cross-app entity types | workspace `packages/types` | an app's `api/` may **re-export**, never redefine |
| Feature-internal types (view models, component state) | inside the feature folder | implementation detail — must not leak into `api/` or packages |
| Store state types | with the store definition | |
| Component prop types | in the component file | |

- API types are **inferred, not authored** — the zod schema is the source of truth; the parse boundary that produces it is owned by `references/4-feature/api-and-pages.md`. A hand-written response type beside a schema is a twin that will drift.
- Cross-app entity types are **owned once** in `packages/types`; an app re-exports, never redefines. Package internals and export surface: `references/3-app/frontend/shared-packages.md`.
- `packages/types` (and `packages/services`) mirror the owning backend's domain names where a mapping exists — the contract vocabulary stays findable end to end.

## The shared invariant — every type has an owner

**No global `types.ts` (frontend) or catch-all `types.py` dump (backend).** A type without an owning feature/domain/component is a type nobody updates. The same rule spans both planes: a type lives at the lowest level that contains all its consumers, and nowhere else. Ownerless code — a `types.ts`, a `context/`, a `helpers/` catch-all — accumulates silently and rots.

## Audit checks

- A global `types.ts` (frontend) or ownerless `types.py` accumulating unrelated types = finding.
- Cross-domain DTO imports in a Python backend (`from app.<other-domain>.models import …` for contract shapes) = coupling finding.
- Two backends importing a shared models package = finding — the DB schema is the only permitted shared contract.
- Hand-written response types sitting next to zod schemas = drift finding — infer instead.
- A local app redefining a type that already exists in `packages/types` (instead of re-exporting) = finding.
- A domain-shared type parked in global `core/` (or an app-wide type buried in one feature) = placement finding.

## Anti-patterns

- A `types.ts` / `types.py` catch-all — ownerless code accumulates silently.
- Cross-domain DTO imports "to reuse a shape" — duplicate the shape; keep contracts independent.
- A shared models package across two backends — couple them through the DB schema, nothing else.
- Hand-written twins of zod-inferred types — twins drift; infer.
- Redefining a `packages/types` entity locally — two sources of truth, immediate drift.

## See also

- `references/4-feature/api-and-pages.md` — the zod parse boundary and api layer that produce the inferred frontend types
- `references/4-feature/feature-folders.md` — the `{router,service,repository,models}.py` feature shape `models.py` DTOs sit in
- `references/3-app/backend/domain-grouping.md` — the domain / `core/` altitude backend types are placed against
- `references/3-app/backend/two-plane-split.md` — why two backends share a DB schema, never a models package
- `references/3-app/backend/migrations.md` — the DB schema as the raw-SQL project's contract
- `references/3-app/frontend/shared-packages.md` — `packages/types` internals and export surface
- `references/4-feature/00_charter.md` — the feature-level charter this reference serves
