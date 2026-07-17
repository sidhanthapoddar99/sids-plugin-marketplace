# Multi-frontend workspaces

When two or more frontends share code (UI primitives, types, API clients, tokens), introduce workspaces. Default: **pnpm + turborepo** for Vite/React. Bun workspaces are a viable alternative.

## When to introduce workspaces

- 2+ frontends that **actually share code** (components, hooks, types, design tokens)
- Without shared code: just have two independent `apps/frontend-*/` folders, no workspace tool needed

Workspaces add: a workspace manifest, hoisting rules, build orchestration (turbo). They're overhead unless real sharing happens.

## Layout

```
my-product/
├── package.json                    # workspace root manifest
├── pnpm-workspace.yaml
├── turbo.json
├── apps/
│   ├── web/                        # main app
│   │   ├── package.json            # depends on @my/ui, @my/styles, ...
│   │   ├── .env / .env.example     # VITE_* scoped to web
│   │   ├── vite.config.ts
│   │   ├── src/
│   │   └── Dockerfile
│   ├── admin/                      # admin dashboard
│   ├── space/                      # public-share frontend
│   ├── live/                       # realtime collab UI
│   └── api/                        # backend(s) can be apps too
├── packages/
│   ├── ui/                         # shadcn primitives + project wrappers
│   │   ├── package.json            # name: "@my/ui"
│   │   └── src/
│   ├── styles/                     # ← tokens.css + globals + light-dark
│   │   ├── package.json            # name: "@my/styles"
│   │   └── src/
│   │       ├── tokens.css
│   │       ├── globals.css
│   │       └── light-dark.css
│   ├── tailwind-config/            # shared tailwind config preset
│   ├── typescript-config/          # base tsconfig
│   ├── eslint-config/
│   ├── hooks/
│   ├── services/                   # API clients
│   ├── types/
│   └── utils/
├── docker/  scripts/  infra/  data/  docs/  .claude/
└── ctl / README / CLAUDE
```

> **`packages/` here = internal shared code** consumed in-repo by the sibling apps. If instead the repo's *deliverable* is a `packages/<pkg>` that an **external** host installs (the package *is* the product, `apps/web` is just a reference host), that's a different layout — see `references/repo-setup/layouts/06_embeddable-package-and-reference-host.md` (peerDeps, `exports`, publishing, embedding seams).

## Workspace rooting + package scope

The tree above roots the workspace at the **repo root** — correct **only for a JS-only repo**, and even then the root `package.json` stays orchestration-only (no runtime deps, no source — `references/repo-setup/root-and-hygiene.md`).

In a **polyglot repo** (Python/Rust backends + JS frontends), the workspace roots at the **frontend group folder** instead, and the repo root stays manifest-free:

```
apps/client/                     # ← workspace root (plane-grouped topology)
├── package.json                 # orchestration-only
├── pnpm-workspace.yaml
├── turbo.json
├── platform/  admin/            # the apps
└── packages/
    ├── ui/  styles/  types/  …  # frontend-only shared packages live INSIDE the group
```

```yaml
# apps/client/pnpm-workspace.yaml — globs are relative to the workspace root
packages:
  - "platform"
  - "admin"
  - "packages/*"
```

`ctl` bridges from the repo root: `ctl dev <app>` / `ctl build` `cd` into the workspace root and delegate to turbo, so commands are location-independent.

**Package scope follows consumers** — a package lives at the lowest level that contains all of them. Frontend-only packages (`ui`, `styles`, `tailwind-config`) belong inside the client group; a package consumed across planes (e.g. `types` shared with a TS backend) forces the hybrid topology — `packages/` at the repo root. The topology decision table is in `references/repo-setup/layouts/02_multi-app-monorepo.md` § "Grouping topology".

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

The `catalog:` section pins shared versions consumed via `"react": "catalog:"` in package manifests — ensures every app uses the same React.

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

**Crucial**: every `VITE_*` / `NEXT_PUBLIC_*` that affects the build must be listed in `globalEnv`. Forgetting one means stale builds.

## `packages/ui/package.json`

```json
{
  "name": "@my/ui",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./button": "./src/button.tsx",
    "./*.css": "./src/*.css"
  },
  "dependencies": {
    "react": "catalog:",
    "@radix-ui/react-slot": "^1.1.0"
  }
}
```

Apps consume via:

```ts
import { Button } from "@my/ui/button";
import "@my/styles/tokens.css";
```

## `packages/styles/package.json`

```json
{
  "name": "@my/styles",
  "private": true,
  "exports": {
    "./tokens.css": "./src/tokens.css",
    "./globals.css": "./src/globals.css",
    "./light-dark.css": "./src/light-dark.css"
  }
}
```

Each app's `main.tsx` imports:

```ts
import "@my/styles/tokens.css";
import "@my/styles/globals.css";
import "@my/styles/light-dark.css";
```

Update tokens in one place; every app picks them up on next build.

## Bun workspaces alternative

Same shape, swap `pnpm-workspace.yaml` for `package.json#workspaces`:

```json
{
  "workspaces": ["apps/*", "packages/*"]
}
```

Bun is simpler but turborepo's cache + task graph is currently the value-add of pnpm + turbo. For pure Vite/React with no SSR, bun workspaces + bun's own bundling can work — try it if you don't need turbo features.

## `ctl` shape

```bash
ctl dev                     # turbo dev — all apps + persistent watch
ctl dev <app>               # turbo dev --filter=<app>
ctl build                   # turbo build
ctl check                   # turbo check — types + lint + format
ctl test                    # turbo test
ctl clean                   # turbo clean + docker
ctl help
```

The wrapper delegates to turbo; turbo handles filter/cache/parallelism.

## Real-world reference

- A large OSS workspace (e.g. Plane: 6 apps + 15 packages, pnpm + turbo) demonstrates this shape at scale — study its `pnpm-workspace.yaml`, `turbo.json`, `apps/web/`, `packages/ui/`.

## Anti-patterns

- Introducing turbo for 2 apps with zero shared code
- Forgetting `globalEnv` entries — cache misses or stale builds
- Putting business logic in `packages/utils` — keep packages reusable and stateless
- One mega `packages/ui` that knows about every app's data — UI primitives only
- Mixing pnpm and bun lockfiles in the same repo
- Rooting the workspace at the repo root of a polyglot repo — `node_modules/` + lockfile clutter a root that other ecosystems share; root at the frontend group folder
- A frontend-only package at root `packages/` (overstates its blast radius), or a cross-plane package buried inside the client group (hides its consumers)
