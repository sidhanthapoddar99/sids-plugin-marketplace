# Topology 04 — monorepo, multi-frontend workspaces

Multiple frontends sharing a UI package, types, tokens, services. Example: `plane` (web/admin/space/live + 15 shared packages, turborepo + pnpm).

## When it fits

- 2+ frontends that **share code** (components, hooks, types, API clients, design tokens)
- They might be: main app + admin dashboard + public-share page + realtime collab UI
- Without shared code → just use Topology 02 twice; don't introduce workspaces

## Tree

```
my-product/
├── .env / .env.example
├── .mise.toml
├── package.json                    # workspace root
├── pnpm-workspace.yaml             # (or bun workspaces)
├── turbo.json                      # globalEnv lists every cache-busting var
├── dev                             # ./dev — dispatches to turbo
├── docker/
├── scripts/
├── apps/
│   ├── web/                        # main app frontend
│   │   ├── package.json
│   │   ├── .env / .env.example     # VITE_* only, web-scoped
│   │   ├── vite.config.ts
│   │   ├── src/
│   │   │   ├── styles/             # imports tokens from packages/styles
│   │   │   ├── components/
│   │   │   └── pages/
│   │   └── Dockerfile
│   ├── admin/                      # admin frontend
│   │   ├── package.json
│   │   ├── .env / .env.example     # VITE_* only, admin-scoped
│   │   └── …
│   ├── space/                      # public-share frontend
│   ├── live/                       # realtime collab
│   ├── api/                        # backend(s) — yes, also under apps/
│   └── proxy/                      # nginx/caddy config as an "app"
├── packages/                       # shared across frontends
│   ├── ui/                         # shadcn components, headless primitives
│   │   ├── package.json
│   │   └── src/
│   ├── styles/                     # ← THE shared tokens.css + globals
│   │   ├── package.json
│   │   └── src/tokens.css          # consumed via `import "@my/styles/tokens.css"`
│   ├── tailwind-config/            # shared tailwind config
│   ├── typescript-config/          # shared tsconfig bases
│   ├── eslint-config/
│   ├── hooks/
│   ├── services/                   # API clients
│   ├── types/                      # TypeScript types
│   └── utils/
├── infra/  data/  docs/  .claude/
└── README.md / CLAUDE.md
```

## Why pnpm + turborepo by default

- **pnpm** — content-addressable installs, strict peer deps, fast in CI
- **turborepo** — task graph + cache. `globalEnv` in `turbo.json` declares which env vars bust the cache when changed. Plane's `globalEnv` lists every `VITE_*` — that's the right pattern.

Bun workspaces are a viable alternative; choose based on team familiarity. For Next/Astro mixes, pnpm + turbo is the safer default.

## `packages/styles` — the shared tokens contract

```
packages/styles/
├── package.json
└── src/
    ├── tokens.css          # design tokens (--bg-*, --fg-*, --space-*, --radius-*)
    ├── globals.css         # body, root, base resets
    └── light-dark.css      # [data-theme="dark"] block
```

Every app imports the same `tokens.css` and consumes via `var(--token)`. No hex, no raw px in component CSS. Updating a token in one place updates every frontend simultaneously.

## Env namespacing

Each frontend has its own `.env`, not the root `.env`. Vars are scoped:

```
apps/web/.env:      VITE_API_BASE_URL=/api  VITE_WEB_BASE_URL=...
apps/admin/.env:    VITE_API_BASE_URL=/api  VITE_ADMIN_BASE_PATH=/admin
apps/space/.env:    VITE_API_BASE_URL=/api  VITE_SPACE_BASE_PATH=/space
```

Root `.env` still holds backend secrets — but **no frontend reads it**.

## `turbo.json` essentials

```json
{
  "globalEnv": [
    "NODE_ENV",
    "VITE_API_BASE_URL",
    "VITE_WEB_BASE_URL",
    "VITE_ADMIN_BASE_URL",
    "VITE_SPACE_BASE_PATH",
    "VITE_LIVE_BASE_URL"
  ],
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "dev":   { "cache": false, "persistent": true },
    "check": { "dependsOn": ["check:types", "check:lint"] },
    "test":  { "dependsOn": ["^build"] }
  }
}
```

Every env var that affects the build belongs in `globalEnv`. Forgetting one means stale caches.

## `./dev` shape

```
./dev                            # turbo dev (all apps)
./dev <app>                      # turbo dev --filter=<app>
./dev build                      # turbo build
./dev check                      # types + lint + format
./dev test
./dev clean
./dev help
```

## Real-world reference

- `plane` — `~/projects/03_Self_Hosted_Apps/plane` — true multi-frontend turborepo. 6 apps + 15 packages. `pnpm-workspace.yaml` + `turbo.json` worth studying.

## Common mistakes to avoid

- Introducing workspaces for two frontends that don't actually share code
- Forgetting to list a `VITE_*` in `turbo.json` globalEnv — stale builds
- Letting one app's `tailwind.config.ts` drift from `packages/tailwind-config`
- Bundling `tokens.css` per app — single source rule violated
