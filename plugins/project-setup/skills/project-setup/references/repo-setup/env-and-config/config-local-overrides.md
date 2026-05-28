# `config.local.yaml` — local-only overrides

A sibling file to `config.yaml` that takes precedence in local dev. Gitignored. Lets a developer tweak settings without modifying the committed config.

## Where it lives

```
apps/backend/
├── config.yaml          # committed, the base
└── config.local.yaml    # gitignored, your overrides
```

Same path pattern for every service that has a `config.yaml`.

## What goes in it

```yaml
# apps/backend/config.local.yaml

app:
  log_level: debug          # base says info; I want debug locally

database:
  echo: true                # log all SQL

redis:
  url: redis://localhost:6379/15    # use db 15 to not collide with other projects

# enable a feature flag for testing
features:
  new_search_ui: true
```

Things that vary per-developer (not per-environment):

- Log levels
- Database connection details when running outside compose (e.g. local Postgres on a non-standard port)
- Feature flag toggles for in-progress work
- Mock service endpoints

Things that vary per-environment go in `config.<env>.yaml` or in env vars.

## Loading order

```
config.yaml
  ├─ overridden by config.<env>.yaml      (committed, env-specific)
  └─ overridden by config.local.yaml      (gitignored, dev-only)
```

Deep merge — nested keys merge field by field; arrays replace whole.

## `.gitignore` pattern

```
config.local.yaml
**/config.local.yaml
```

Or more loosely, ignore any `*.local.yaml`:

```
*.local.yaml
**/*.local.yaml
```

## Why not `.env.local`?

`.env.local` is a thing too (and Vite, Next read it). But:

- `.env.local` is for **runtime env vars**
- `config.local.yaml` is for **structured config**, can include arrays/objects/nested keys
- The two coexist — they're for different layers

A typical dev has both: a `.env.local` with their personal API keys, and a `config.local.yaml` with their preferred log levels.

## Anti-patterns

- Committing `config.local.yaml` — defeats the purpose
- Encoding secrets in `config.local.yaml` — those belong in `.env.local` instead, then referenced via `${VAR}`
- Using `config.local.yaml` to enable production-only features — those are `config.production.yaml` overrides
- Having no `config.local.yaml` mechanism at all and forcing every developer to edit `config.yaml` (gets accidentally committed)
