# Frontend workspaces — config-body mechanics

Recipes only, zero decisions. This file owns the **config file bodies** for a pnpm + turborepo frontend workspace (the default for Vite/React): the root manifest, `pnpm-workspace.yaml` + `catalog:`, `turbo.json` + `globalEnv`, the bun alternative, and the `ctl` delegation surface. Copy these; do not re-derive them.

The decisions these bodies serve live elsewhere: whether to introduce a workspace at all (2+ frontends that actually share code) is **owned by `references/2-repo/layouts/02_multi-app-monorepo.md` § "Scaling: more than one frontend"**; where the workspace roots (repo root for JS-only, frontend group folder for polyglot) and which scope each package sits at are **owned by `references/2-repo/grouping-topology.md`**. Package internals (export surface, what lives in each package, tailwind wiring, tripwire T4) are **owned by `references/3-app/frontend/shared-packages.md`**.

## Where the config files sit

The workspace root holds orchestration-only manifests — no runtime deps, no source (`references/2-repo/root-and-hygiene.md`, tripwire T10):

```
<workspace-root>/          # repo root (JS-only) OR the frontend group folder (polyglot)
├── package.json           # orchestration scripts → turbo
├── pnpm-workspace.yaml     # workspace globs + catalog + build allowlist
├── turbo.json             # task graph + globalEnv
├── apps/                  # the apps (placement → grouping-topology.md)
└── packages/              # shared packages (internals → shared-packages.md)
```

## Root `package.json`

```json
{
  "name": "my-product-workspace",
  "private": true,
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "check": "turbo check",
    "test": "turbo test"
  },
  "packageManager": "pnpm@9.12.0"
}
```

## `pnpm-workspace.yaml`

```yaml
packages:
  - apps/*
  - packages/*
  - "!apps/api"           # exclude non-JS apps from pnpm

catalog:
  react: 19.0.0
  react-dom: 19.0.0
  vite: 5.4.0
  typescript: 5.6.0
  "@types/react": 19.0.0

onlyBuiltDependencies:
  - turbo
```

The `catalog:` section pins shared versions once; package manifests consume them via `"react": "catalog:"`, so every app resolves the same React. Globs are relative to the workspace root, so the **polyglot** variant (workspace rooted at the frontend group folder) uses group-relative globs — the same file, different anchor:

```yaml
# apps/client/pnpm-workspace.yaml — rooted at the group folder
packages:
  - "platform"
  - "admin"
  - "packages/*"
```

Rooting choice (why the anchor moves) → `references/2-repo/grouping-topology.md`.

## `turbo.json`

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalEnv": [
    "NODE_ENV",
    "VITE_API_BASE_URL",
    "VITE_WEB_BASE_URL",
    "VITE_ADMIN_BASE_URL",
    "VITE_SPACE_BASE_PATH",
    "VITE_LIVE_BASE_URL",
    "VITE_SENTRY_DSN"
  ],
  "globalDependencies": ["pnpm-lock.yaml", "pnpm-workspace.yaml"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", "build/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "check:types":  { "dependsOn": ["^build"], "cache": false },
    "check:lint":   { "cache": false },
    "check:format": { "cache": false },
    "check":        { "dependsOn": ["check:format", "check:lint", "check:types"], "cache": false },
    "test":         { "dependsOn": ["^build"] },
    "clean":        { "cache": false }
  }
}
```

**Every `VITE_*` / `NEXT_PUBLIC_*` that affects the build must be listed in `globalEnv`.** Omitting one means turbo's cache key misses that variable — stale builds from a warm cache. Build-var isolation itself (which prefix leaks to the client) is owned by `references/2-repo/env-and-config/frontend-env-isolation.md`.

## Bun workspaces alternative

Same tree, same package layout — swap `pnpm-workspace.yaml` for a `workspaces` field in the root `package.json`:

```json
{
  "workspaces": ["apps/*", "packages/*"]
}
```

Bun is simpler but turborepo's cache + task graph is the value-add of pnpm + turbo. For pure Vite/React with no SSR, bun workspaces + bun's own bundling can work — try it when you don't need turbo's cache/graph features. Never mix pnpm and bun lockfiles in one repo.

## `ctl` shape

The dispatcher delegates to turbo; turbo owns filter/cache/parallelism. In a polyglot repo `ctl` bridges from the repo root by `cd`-ing into the workspace root before delegating, so commands stay location-independent.

```bash
ctl dev                     # turbo dev — all apps + persistent watch
ctl dev <app>               # turbo dev --filter=<app>
ctl build                   # turbo build
ctl check                   # turbo check — types + lint + format
ctl test                    # turbo test
ctl clean                   # turbo clean + docker
ctl help
```

`ctl`'s broader shape (dev vs up axes, size tripwire T7) is owned by `references/2-repo/runtime/script-overview.md`.

## Anti-patterns

- Forgetting a `globalEnv` entry — cache hits serve stale builds.
- Mixing pnpm and bun lockfiles in the same repo — pick one package manager.
- Runtime deps or source in the workspace-root manifest — root stays orchestration-only (tripwire T10).
- Hardcoding a version in a manifest that a `catalog:` entry already pins — drift between apps.

## See also

- `references/2-repo/grouping-topology.md` — when to introduce a workspace, rooting, package placement (the decisions these bodies serve)
- `references/3-app/frontend/shared-packages.md` — what lives inside `packages/*`, export surface, tailwind wiring, T4
- `references/3-app/frontend/app-skeleton.md` — the app's own `src/` skeleton and workspace reconciliation
- `references/2-repo/root-and-hygiene.md` — orchestration-only root manifest (T10)
- `references/00_altitude-model.md` — master tripwire table
