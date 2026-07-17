# Frontend app skeleton — the structure of a frontend

**The answer to "how is a frontend structured".** This file owns where a frontend app sits, its root config files, the entry pair (`index.html` + `main.tsx`), the **hard `src/` skeleton** every frontend keeps, the layer import-rules that hold it together, how `layout/` shells subdivide, and the workspace-reconciliation rule (local folders vs shared packages). What lives *inside* `api/`, `pages/`, and the type layers is L4 detail and moves out — see the links below. Applies to every Vite/React app; Next/Astro keep the same doctrine with the framework's router in place of `pages/` (`references/3-app/frontend/framework-variants.md`).

## App placement + root config

A single frontend sits at `apps/frontend/`. In a multi-app repo the app's slot (flat `apps/web/` vs plane-grouped `apps/client/<name>/`) and the workspace root are **owned by `references/2-repo/grouping-topology.md`** — don't restate. Whatever the slot, the app root holds this fixed set:

| File / dir | Purpose |
|---|---|
| `package.json` + lockfile | app manifest (deps here, never at repo root — tripwire T10, owned by `references/2-repo/root-and-hygiene.md`) |
| `.env` / `.env.example` | **`VITE_*` only** — leak rules owned by `references/2-repo/env-and-config/frontend-env-isolation.md` |
| `config.yaml` | optional dev metadata |
| `vite.config.ts` | build + the dev `/api` proxy (proxy↔nginx pair owned by `references/2-repo/deployment/proxy-and-exposure.md`) |
| `tailwind.config.ts` | Tailwind preset (shared preset wiring → `references/3-app/frontend/tokens-setup.md`) |
| `tsconfig.json` | TS config |
| `postcss.config.cjs` | PostCSS (autoprefixer) |
| `index.html` | Vite entry HTML — template below |
| `public/` | static assets served as-is |
| `src/` | the skeleton — see below |
| `Dockerfile` | prod image (multi-stage build → nginx serve) |
| `nginx/nginx.conf` | optional — bundled prod-stage nginx config |

### `index.html`

```html
<!DOCTYPE html>
<html lang="en" data-theme="light">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>%VITE_APP_NAME%</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

`data-theme="light"` on `<html>` is the default the app toggles to `"dark"`; the mechanism is owned by `references/3-app/frontend/tokens-setup.md`.

### `main.tsx`

```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App.tsx";

// Order matters: tokens before everything
import "./styles/tokens.css";
import "./styles/globals.css";
import "./styles/elements.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

`App.tsx` is the top-level component + router config and **imports pages only**. In a workspace the three style imports come from `@my/styles` instead of local `./styles/` (see workspace reconciliation below; token file contents owned by `references/3-app/frontend/tokens-setup.md`).

### Default deps

```json
{
  "dependencies": {
    "react": "^19",
    "react-dom": "^19",
    "react-router-dom": "^6"
  },
  "devDependencies": {
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "@vitejs/plugin-react": "^4",
    "autoprefixer": "^10",
    "biome": "^1.9",
    "postcss": "^8",
    "tailwindcss": "^3.4",
    "typescript": "^5.6",
    "vite": "^5"
  }
}
```

Plus whatever shadcn pulls in (Radix primitives) and project libs (Zustand, TanStack Query, React Hook Form + Zod).

## The canonical `src/` skeleton

The **top level of `src/` is a hard skeleton** — these names, this altitude. What's inside each folder is project-specific. Folders are **not** pre-created: the skeleton defines where a thing goes *when it appears*, not a set of placeholder directories.

```
src/
├── main.tsx      # entry — mounts <App /> on #root
├── App.tsx       # top-level component + router config (imports pages only)
├── layout/       # app shells / structural frames (sidebar+topbar, auth frame, print frame)
├── components/   # common composed components (page header, empty state) + ui/ primitives (standalone apps)
├── features/     # per-feature substance — subdivided; internals owned by 4-feature
├── pages/        # thin route components mirroring the URL tree; compose from features/
├── hooks/        # shared hooks (feature-specific hooks live in their feature)
├── api/          # THE api access layer — all server communication; internals owned by 4-feature
├── lib/          # pure utilities (formatters, parsers — no React, no IO)
├── stores/       # client state (zustand or equivalent); server state belongs to api/
└── styles/       # tokens.css + globals — ONLY when no workspace styles package exists
tests/            # cross-cutting test setup (fixtures, msw server); unit tests co-locate with source
public/           # static assets served as-is
```

| Folder | Contents |
|---|---|
| `styles/` | All CSS. Contents + discipline owned by `references/3-app/frontend/tokens-setup.md`. Replaced by `packages/styles` in a workspace. |
| `layout/` | App shells. Each shell subdivides into its own folder once it outgrows one file (see below). |
| `components/ui/` | shadcn primitives + wrappers — standalone apps only. Edit freely (copy-not-import). Graduates to `packages/ui` in a workspace. |
| `features/` | Per-feature substance. Folders by feature; subdivision (tripwire T3) + internals owned by `references/4-feature/api-and-pages.md`. |
| `pages/` | Thin route components mirroring the URL tree; compose from `features/`. Thinness (tripwire T6) owned by `references/4-feature/api-and-pages.md`. |
| `api/` | The only place server communication lives. Endpoint/zod/error/query-key doctrine owned by `references/4-feature/api-and-pages.md`. |

Context providers co-locate with what they provide (theme → `layout/` or the ui package; session → `api/` or the services package). No `context/` catch-all folder — it's a kind-folder.

### Layer import rules

The skeleton holds only if the layers stay one-directional:

| Folder | May import from | Never contains |
|---|---|---|
| `pages/` | `features/`, `layout/`, `components/` | business logic, fetch calls, files past the T6 thinness threshold |
| `features/` | `api/`, `components/`, `hooks/`, `lib/`, `stores/`, ui package | raw `fetch`/axios, route wiring |
| `layout/` | `components/`, ui package | feature knowledge |
| `components/` | ui package, `lib/` | server communication, feature-specific logic |
| `api/` | `lib/`, `packages/types` | React components |
| `lib/` | nothing app-internal | React, IO |

### `layout/` subdivides like everything else

Each shell starts as a single file (`layout/app-shell.tsx`). A shell that grows past one file gets its own subfolder that owns all its parts:

```
layout/
├── app-shell/          # grew: frame + its pieces travel together
│   ├── index.tsx
│   ├── sidebar.tsx
│   └── topbar.tsx
├── auth-frame.tsx      # still one file — stays flat
└── settings-frame.tsx
```

This is the general skeleton rule applied recursively: **skeleton names are firm; each entry subdivides when it outgrows a single file** — never a flat pile of `sidebar2.tsx` siblings, never a premature folder for a 40-line frame. The same rule governs feature folders (T3) and ui packages (T4), owned elsewhere.

## Workspace reconciliation — packages replace local folders

In a multi-frontend workspace, three of these layers graduate to shared packages and must **not** be duplicated locally:

| Standalone app | Workspace equivalent |
|---|---|
| `components/ui/` (shadcn primitives + wrappers) | `packages/ui` |
| `styles/` (tokens.css, globals, light-dark) | `packages/styles` |
| auth/session services + API clients shared across apps | `packages/services` |

Both variants are legitimate — the rule is **never both**. A local `components/ui/` beside an existing `packages/ui` (or a local `styles/` beside `packages/styles`) is a red audit finding: two sources of truth drift immediately. Shared code lives at the lowest level that contains all its consumers; once a second app consumes a layer, that level is the workspace package.

- **Package placement** (which scope) + workspace rooting → `references/2-repo/grouping-topology.md`.
- **Package internals** (export surface, `~15`-component grouping T4, tailwind wiring) → `references/3-app/frontend/shared-packages.md`.
- **Workspace mechanics** (pnpm/turbo/bun config bodies, catalog, `globalEnv`, `ctl` shape) → `references/3-app/frontend/workspaces-mechanics.md`.

## When to add complexity

| Trigger | Action |
|---|---|
| Second frontend that shares any code | Introduce a workspace (`packages/ui`, `packages/styles`) — `references/2-repo/grouping-topology.md` |
| Server-rendering required | Switch to Next.js or Astro — `references/3-app/frontend/framework-variants.md` |
| Repo's deliverable is the package, not the app | Embeddable layout — `references/2-repo/layouts/06_embeddable-package.md`, seams in `references/3-app/frontend/embeddable-seams.md` |
| PWA / offline mode | Add `vite-plugin-pwa` + Workbox |
| Heavy state | Add Zustand (local) + TanStack Query (server) |
| Forms | Add React Hook Form + Zod |

## Audit checks

- `src/` present at the repo root instead of under an app folder → finding (the "no `src/` at root" hard rule — `SKILL.md`, `references/02_decision-tree.md`).
- Missing skeleton layers in a grown app — routes importing feature internals because `pages/` doesn't exist, fetch logic inside features because `api/` doesn't exist → finding.
- A layer importing against the layer rules (e.g. `components/` doing server communication, `lib/` importing React) → finding.
- A local `components/ui/` or `styles/` coexisting with the workspace package → red finding.
- `tokens.css` outside `styles/` (standalone) or outside `packages/styles` (workspace) → finding.
- `index.html` missing its `data-theme` attribute → finding (light/dark toggle breaks).

## Anti-patterns

- `src/` at repo root, not under `apps/<app>/`.
- A `context/`, `helpers/`, or `types.ts` catch-all at the top of `src/` — ownerless code accumulates silently.
- Runtime deps in the repo-root `package.json` instead of the app manifest (T10).
- Duplicating a workspace package locally "to move fast" — two sources of truth.
- A premature `layout/<shell>/` folder for a 40-line frame, or a flat pile of `sidebar2.tsx` siblings — subdivide on outgrowth, not before or never.
- Skipping `index.html`'s `data-theme` attribute — light/dark toggle becomes awkward.

## See also

- `references/4-feature/api-and-pages.md` — `api/` internals (endpoints, zod, error norm, query keys, fetch grep), `pages/` vs `features/`, tripwires T3/T6
- `references/4-feature/types-and-contracts.md` — where every kind of type/DTO lives
- `references/3-app/frontend/tokens-setup.md` — `styles/` contents, light/dark data-attr, shadcn/tailwind wiring
- `references/3-app/frontend/shared-packages.md` — package internals + export surface (T4)
- `references/3-app/frontend/workspaces-mechanics.md` — pnpm/turbo/bun config bodies, `ctl` shape
- `references/2-repo/grouping-topology.md` — app slots, workspace rooting, package placement
- `references/4-feature/styling-discipline.md` — the primitive-first styling rules feature code lives under
- `references/3-app/00_charter.md` — the L3 app charter this reference serves
