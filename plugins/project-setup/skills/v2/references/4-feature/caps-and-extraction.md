# Caps & extraction — file caps, rule of N, folders by feature

The L4 modularity owner. Holds three settled rules and their tripwires: **file-size caps (T5)**, the **rule-of-N extraction family (T9 logic, T8 styling)**, and **folders by feature, not by kind** (plus kind-folder exceptions and test co-location). These are continuous-development rules — installed in CLAUDE.md, enforced by audit, never asked at bootstrap. The domain-layer ceiling above feature folders links out to L3.

## File size caps — 500 hard / 300 soft (T5)

Hard rule for any code in this project: **500 lines per file, max.** Past that, split before committing. Soft target is 300 — past which look for a natural split.

**The cap applies to:** source code (Python, TS, Rust, Go, etc.); hand-authored test files; component files.

**The cap does NOT apply to:** generated artefacts (sqlx `.sqlx/`, Alembic auto-generated migrations, Tailwind config, OpenAPI codegen output); vendored content (third-party code copied in); lockfiles, `package.json`; data files (JSON fixtures, large constants).

### Why a cap

- **Mental load** — 500 lines is roughly the limit a reader can hold context for in a single sitting
- **Diff readability** — large files produce large diffs nobody reviews properly
- **Test isolation** — split files often map to split test files
- **Find/grep ergonomics** — knowing `auth/jwt.ts` exists is better than searching a 1500-line `auth.ts`

### Natural split signals

If a file is approaching 300 lines, watch for:

- **Two responsibilities** sharing the file ("user CRUD + email sending")
- **One large type / class** with many methods that group thematically (extract groups to separate files)
- **Repeated patterns** that could become helpers (the rule of three — below)
- **Imports** crossing 30 lines — usually means the file does too much

### How to split

| Pattern | Split into |
|---|---|
| `users.py` with CRUD + permissions + email | `users/crud.py`, `users/permissions.py`, `users/email.py`, `users/__init__.py` re-exports |
| `Dashboard.tsx` with 5 sub-components inline | `Dashboard/Dashboard.tsx`, `Dashboard/Card.tsx`, `Dashboard/Filter.tsx`, `Dashboard/index.tsx` re-exports |
| Rust `module.rs` with many public structs | `module/mod.rs` + `module/<struct>.rs` per struct, re-exported in `mod.rs` |

Split **vertically by feature** (below), not horizontally by kind.

### Enforcement

Lint rule (varies per language). For TS/JS, biome:

```json
{
  "linter": {
    "rules": {
      "complexity": {
        "noExcessiveCognitiveComplexity": { "level": "warn", "options": { "maxAllowedComplexity": 15 } }
      }
    }
  }
}
```

(Cognitive complexity is a related-but-different metric; lines-per-file is harder to enforce without custom tooling. The discipline is mostly cultural — caught in review.)

A simple repo-level CI check:

```bash
# .github/workflows/checks.yml
- name: file-size-cap
  run: |
    find apps packages -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.rs' \) \
      -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/target/*' \
      -exec wc -l {} + \
      | awk '$1 > 500 && $2 != "total" { print; found=1 } END { exit found }'
```

### When to relax

- Generated code (already excluded)
- Test fixtures / large data inline
- Configuration files with many keys (e.g. tailwind config — read top-to-bottom, no logic)
- A genuine monolithic algorithm where splitting would obscure (rare)

When relaxing, comment why at the top of the file.

## Extract on third use — the rule of three (T9)

When you see the same pattern repeating, **count uses before extracting**:

- **1 use** — inline
- **2 uses** — duplicate (cheap; might diverge)
- **3 uses** — extract a shared helper

Pre-emptive abstraction is more expensive than duplication. Three similar lines is better than a premature abstraction.

### Why

- **Premature abstraction has a discovery cost** — readers must follow it to understand the call site
- **The "abstraction" often doesn't fit** — the third use reveals which parameters actually generalise
- **Duplication is reversible** — abstraction is harder to undo

### In practice

| Situation | Action |
|---|---|
| `if user.is_admin or user.is_owner` appears once | inline |
| Same condition in two functions | inline both — they might diverge |
| Same condition in three functions across two files | extract `def can_manage(user) -> bool` |

The extract should be **named for what it means**, not for what it does mechanically.

**What counts as "the same":** same logic + same shape (not just syntactic similarity); same business meaning ("a user can manage this resource" — not "two if-checks"); not just same return type — a `bool` from two different rules stays two functions.

**What does not count:** boilerplate the framework demands (FastAPI route signatures, React hook structure) — that's the framework, not your duplication; similar shapes with different meaning; sequential lines in two files that happen to use the same APIs for different reasons.

### Counter-rule: extract earlier when

- The pattern is **non-obvious** (clever algorithm, tricky regex) — extract on first use with a name, so callers don't have to understand
- The pattern is **dangerous** (security-sensitive crypto, parsing untrusted input) — extract on first use to centralise review
- The pattern is **owned by a different layer** (DB query, HTTP call) — extract immediately into the appropriate module
- The pattern is **a styling utility combination** — fold into a primitive variant on the **second** use (T8, below)

The one-line form for a project CLAUDE.md: *"Three usages of similar code is the trigger for shared helpers; one or two is fine to inline."*

## Rule of two for styling (T8)

The styling counterpart to the rule of three: **the same utility combination appearing twice → fold it into a ui-package primitive variant** before continuing. The threshold is 2, not 3, because a utility string is cheaper to extract than a logic abstraction, and styling duplication is where agent visual drift starts. This is the family-member number; the styling-specific mechanics (which primitive, CVA variants, the grep checks, the CLAUDE.md precedence over `frontend-design`) are owned by `references/4-feature/styling-discipline.md`.

## Folders by feature, not by kind

Group code by what it **does**, not what it **is**. When you split a file (T5) or a feature grows, group by feature (`auth/`, `blocks/`, `workspaces/`) — each owns its routes + models + services + tests.

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

### Why

- **One feature, one folder** — to find or change "how auth works", you open `auth/`, not three different trees
- **Cohesion** — files that change together live together
- **Discoverability** — newcomers map repo structure to product features, not framework concepts
- **Easy extraction** — if auth gets big enough to be its own service, copy the folder

### When kind-folders are tempting

Frameworks often suggest `controllers/`, `models/`, `views/` directly. Resist for non-trivial apps. Use them only when:

- The framework genuinely requires it (Rails Convention over Configuration)
- The app is tiny (5 files total)
- The "kinds" are the right axis (e.g. a pure ETL where transforms are interchangeable)

### How to migrate

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

### Shared infrastructure

`shared/` (or `core/`, `common/`, `lib/`) holds truly cross-cutting code: DB connection, exception types, error-handling middleware. **Not** business logic from any one feature.

### Tests co-located

Where the language supports it, tests live next to code:

| Language | Pattern |
|---|---|
| Rust | `#[cfg(test)] mod tests { ... }` in the same file |
| TS | `auth/auth.test.ts` next to `auth/auth.ts` |
| Python | `tests/<feature>/` mirroring `src/<feature>/`, or `src/<feature>/tests/` |

The rule scales up: a workspace's `crates/` (or `packages/`) can be pure feature-folders at the workspace level — each crate one feature (api/data/auth/sync/search). See `references/handoffs/examples-registry.md` — cite a registered repo demonstrating this if one exists.

## The domain-layer ceiling

Feature folders are the organising unit **up to ~8–10 of them**. Past that — or once the product's domain model settles — the flat list itself stops communicating the product, and a **domain layer** goes above it: `app/<domain>/<feature>/`. That threshold (T2), the domain naming rules, feature-seam boundaries, and the adapter-modules pattern are owned by `references/3-app/backend/domain-grouping.md`.

Feature folders also subdivide **internally** past ~10 source files (T3): backend feature-folder internals are owned by `references/4-feature/feature-folders.md`; the frontend twin (`api/`, thin `pages/`) by `references/4-feature/api-and-pages.md`.

## Audit checks

- No hand-authored source/test/component file over 500 lines; files over 300 have a recorded reason or a natural split (T5)
- No logic pattern duplicated in 3+ places without a named helper; no premature single-use abstraction (T9)
- No repeated utility-string combination in feature code (T8 → styling-discipline.md greps)
- No per-kind buckets (`controllers/`, `models/`, `services/`) scattering one feature across the tree; no catch-all `helpers/`/`utils/`/`common/`
- Feature-folder count within ~8–10 or a recorded domain layer (T2 → domain-grouping.md)

## Anti-patterns

- 800-line files that "we'll refactor later" — refactor now
- Splitting prematurely (one type per file when 5 cohesive types fit in one) — soft target is 300, not 30
- Hiding length with short variable names — readability first
- "I might need this later" / extract on the second use "just to be safe" — second uses often diverge (styling is the deliberate exception, T8)
- Helper functions named `process_data`, `handle_thing`, or generic "framework" code you wrote yourself — frameworks are full-time work; you have a job
- Refusing to extract on the 4th, 5th, 6th use — at some point duplication itself becomes the problem
- `helpers/`, `utils/`, `common/` as catch-alls — `auth/helpers.py` is auth-scoped; reach for `shared/` only if 3+ features actually need it
- Per-feature folders with a single 1500-line `index.ts` inside — the size cap still applies
- Per-kind folders with deep per-feature nesting (`routes/auth/`, `models/auth/`) — pick one organising axis
- Naming a global `services/` folder when you mean "business logic" — `service.py` per feature is fine

## See also

- `references/3-app/backend/domain-grouping.md` — the domain-layer ceiling (T2), naming, feature seams
- `references/4-feature/feature-folders.md` — backend feature-folder internals + subdivision (T3)
- `references/4-feature/api-and-pages.md` — frontend feature subdivision, thin pages (T6)
- `references/4-feature/styling-discipline.md` — the styling-specific side of T8 (primitive variants, greps)
- `references/handoffs/examples-registry.md` — registered repos illustrating feature-folder layouts
