# File size caps — 500 hard, 300 soft

Hard rule for any code in this project: **500 lines per file, max.** Past that, split before committing. Soft target is 300 — past which look for a natural split.

## The cap applies to

- Source code (Python, TS, Rust, Go, etc.)
- Hand-authored test files
- Component files

## The cap does NOT apply to

- Generated artefacts (sqlx `.sqlx/`, Alembic auto-generated migrations, Tailwind config, OpenAPI codegen output)
- Vendored content (third-party code copied in)
- Lockfiles, package.json
- Data files (JSON fixtures, large constants)

## Why a cap

- **Mental load** — 500 lines is roughly the limit a reader can hold context for in a single sitting
- **Diff readability** — large files produce large diffs nobody reviews properly
- **Test isolation** — split files often map to split test files
- **Find/grep ergonomics** — knowing `auth/jwt.ts` exists is better than searching a 1500-line `auth.ts`

## Natural split signals

If a file is approaching 300 lines, watch for:

- **Two responsibilities** sharing the file ("user CRUD + email sending")
- **One large type / class** with many methods that group thematically (extract groups to separate files)
- **Repeated patterns** that could become helpers (rule of three — see `extract-on-third-use.md`)
- **Imports** crossing 30 lines — usually means the file does too much

## How to split

| Pattern | Split into |
|---|---|
| `users.py` with CRUD + permissions + email | `users/crud.py`, `users/permissions.py`, `users/email.py`, `users/__init__.py` re-exports |
| `Dashboard.tsx` with 5 sub-components inline | `Dashboard/Dashboard.tsx`, `Dashboard/Card.tsx`, `Dashboard/Filter.tsx`, `Dashboard/index.tsx` re-exports |
| Rust `module.rs` with many public structs | `module/mod.rs` + `module/<struct>.rs` per struct, re-exported in `mod.rs` |

## Folders by feature, not by kind

When splitting, group by feature (`auth/`, `blocks/`, `workspaces/`) — each owns its routes + models + services + tests.

Avoid: generic `controllers/`, `models/`, `helpers/` buckets that scatter one feature across the tree. See `folders-by-feature.md`.

## Enforcement

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

## When to relax

- Generated code (already excluded)
- Test fixtures / large data inline
- Configuration files with many keys (e.g. tailwind config — read top-to-bottom, no logic)
- A genuine monolithic algorithm where splitting would obscure (rare)

When relaxing, comment why at the top of the file.

## Anti-patterns

- 800-line files that "we'll refactor later" — refactor now
- Splitting prematurely (one type per file when 5 cohesive types fit in one) — soft target is 300, not 30
- Hiding length with short variable names — readability first
- Splitting horizontally (controllers/users.ts, models/users.ts, helpers/users.ts) — split vertically by feature
