# memory/ — the working rules

One file per rule set, flat, kebab-case. `AGENTS.md` imports each with `@memory/<file>.md`, so every agent reads them without being told.

| File | Holds |
|---|---|
| `rules.md` | The five rules that bind every change: ctl only, env by role, migrations only, no cross-app imports, no frontend env. |

Add a file when a rule set earns one (`styling.md`, `review.md`). Add its row here and its `@memory/` line in `AGENTS.md` in the same change.
