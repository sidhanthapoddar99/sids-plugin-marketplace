# Folders by feature, not by kind

Group code by what it **does**, not what it **is**.

## The rule

✅ — by feature:

```
src/
├── auth/
│   ├── routes.py
│   ├── models.py
│   ├── service.py
│   ├── schemas.py
│   └── tests.py
├── workspaces/
│   ├── routes.py
│   ├── models.py
│   ├── service.py
│   └── …
└── blocks/
    └── …
```

❌ — by kind:

```
src/
├── routes/
│   ├── auth.py
│   ├── workspaces.py
│   └── blocks.py
├── models/
│   ├── user.py
│   ├── workspace.py
│   └── block.py
└── services/
    ├── auth_service.py
    └── …
```

## Why

- **One feature, one folder** — to find or change "how auth works", you open `auth/`. Not three different trees.
- **Cohesion** — files that change together live together.
- **Discoverability** — newcomers map repo structure to product features, not framework concepts.
- **Easy extraction** — if auth gets big enough to be its own service, copy the folder.

## When kind-folders are tempting

Frameworks often suggest `controllers/`, `models/`, `views/` directly. Resist for non-trivial apps. Use them only when:

- The framework genuinely requires it (Rails Convention over Configuration)
- The app is tiny (5 files total)
- The "kinds" are the right axis (e.g. a pure ETL where transforms are interchangeable)

## How to migrate

A flat `routes.py` + `models.py` codebase becomes:

```
# before
src/
├── main.py
├── routes.py        # 600 lines
├── models.py        # 400 lines
└── services.py      # 800 lines

# after
src/
├── main.py
├── auth/
│   ├── routes.py     # ~120 lines
│   ├── models.py     # ~80 lines
│   └── service.py    # ~200 lines
├── workspaces/
│   ├── routes.py
│   ├── models.py
│   └── service.py
├── blocks/
│   ├── routes.py
│   ├── models.py
│   └── service.py
└── shared/
    ├── db.py
    └── exceptions.py
```

Most files now under the 300-line soft target.

## Shared infrastructure

`shared/` (or `core/`, `common/`, `lib/`) holds truly cross-cutting code: DB connection, exception types, error handling middleware. **Not** business logic from any one feature.

## Tests co-located

Where the language supports it, tests live next to code:

| Language | Pattern |
|---|---|
| Rust | `#[cfg(test)] mod tests { ... }` in the same file |
| TS | `auth/auth.test.ts` next to `auth/auth.ts` |
| Python | `tests/<feature>/` mirroring `src/<feature>/`, or `src/<feature>/tests/` |

## Real-world reference

- The rule scales up: a Rust workspace's `crates/` can be pure feature-folders at the workspace level (api/data/auth/sync/search — each crate one feature).
- See `references/integrations/examples-index.md` — cite a registered repo demonstrating this if one exists.

## Anti-patterns

- `helpers/`, `utils/`, `common/` as catch-alls — over time, they accumulate everything. Better: `auth/helpers.py` is auth-scoped; reach for `shared/` only if 3+ features actually need it.
- Per-feature folders with a single 1500-line `index.ts` inside — the size cap still applies
- Per-kind folders with deep per-feature nesting (`routes/auth/`, `models/auth/`) — pick one organising axis
- Naming `services/` when you mean "business logic" — `service.py` per feature is fine; a global `services/` folder is not

## This rule has a ceiling

Feature folders are the organising unit **up to ~8–10 of them**. Past that — or once the product's domain model settles — the flat list itself stops communicating the product, and a **domain layer** goes above it: `app/<domain>/<feature>/`. That threshold, the domain naming rules, feature-seam boundaries, and the adapter-modules pattern are owned by `references/architecture/modularity/domain-grouping-tripwire.md`. Feature folders also subdivide *internally* past ~10 files (frontend twin: `references/architecture/frontend/intra-app-structure.md`).
