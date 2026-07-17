# Single frontend — Layout 02

The default frontend setup: one Vite + React + TS + Tailwind + shadcn/ui app under `apps/frontend/`.

## Tree

```
apps/frontend/
├── package.json
├── bun.lockb
├── .env / .env.example          # VITE_* only
├── config.yaml                  # optional — dev metadata
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── postcss.config.cjs
├── index.html
├── public/                      # static assets served as-is
├── src/
│   ├── main.tsx                 # entry — mounts <App /> on #root
│   ├── App.tsx                  # top-level component + router config (imports pages only)
│   ├── styles/
│   │   ├── tokens.css           # design tokens
│   │   ├── globals.css          # body, root, base resets
│   │   └── elements.css         # base element overrides
│   ├── layout/                  # app shells (sidebar+topbar frame, auth frame)
│   ├── components/
│   │   ├── ui/                  # shadcn primitives + project wrappers
│   │   └── …                    # common composed components (page header, empty state)
│   ├── features/                # per-feature substance — subdivided past ~10 files
│   ├── pages/                   # thin route components mirroring the URL tree
│   ├── hooks/                   # shared hooks
│   ├── api/                     # THE api access layer — endpoints, zod parsing, query keys
│   ├── lib/                     # pure utilities (no React, no IO)
│   └── stores/                  # client state (zustand or equivalent)
├── Dockerfile
└── nginx/                       # optional — bundle nginx config for prod stage
    └── nginx.conf
```

## What's in each subfolder

The skeleton below `src/` — layer rules, the api-layer doctrine, type placement, and the feature-subdivision tripwire — is owned by `references/architecture/frontend/intra-app-structure.md`. Summary:

| Folder | Contents |
|---|---|
| `src/styles/` | All CSS. `tokens.css` is the only place hex/px live; everything else uses `var(--token)`. |
| `src/layout/` | App shells — sidebar+topbar frame, auth frame. Each shell subdivides into its own folder once it outgrows one file. |
| `src/components/ui/` | shadcn-generated primitives + wrappers. Edit freely (shadcn is copy-not-import). Graduates to `packages/ui` in a workspace. |
| `src/components/` | Common composed components — page header, empty states, confirm dialog. |
| `src/features/` | Per-feature substance. Folders by feature; subdivide past ~10 files. |
| `src/pages/` | Thin route components (~50 lines) mirroring the URL tree; compose from `features/`. Router imports pages only. |
| `src/api/` | The only place server communication lives — endpoint paths, zod parsing at the boundary, error normalization, query keys. |
| `src/hooks/` | Shared hooks (feature-specific hooks live in their feature). |
| `src/lib/` | Pure utilities — formatters, parsers. No React, no IO. |
| `src/stores/` | Client state (zustand or equivalent). Server state belongs to the query layer in `api/`. |

Context providers co-locate with what they provide (theme → `layout/` or the ui package; session → `api/`); no `context/` catch-all folder.

## `index.html` template

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

The `data-theme="light"` attribute on `<html>` is the default; the app toggles it to `"dark"` on theme change. See `light-dark-data-attr.md`.

## `main.tsx`

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

## Default deps

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

Plus whatever shadcn pulls in (Radix primitives, etc.) and the project-specific libs (Zustand, TanStack Query, etc.).

## When to add complexity

| Trigger | Action |
|---|---|
| Second frontend that shares any code | Migrate to Layout 02 (`packages/ui`, `packages/styles`) |
| Server-rendering required | Switch to Next.js or Astro variants |
| PWA / offline mode | Add `vite-plugin-pwa` + Workbox |
| Heavy state | Add Zustand (local) + TanStack Query (server) |
| Forms | Add React Hook Form + Zod |

## Anti-patterns

- `src/` at repo root, not under `apps/frontend/` — see the "no src/ at root" hard rule in `SKILL.md` and `references/00_decision-tree.md`
- Component files past 500 lines — split
- Putting `tokens.css` outside `src/styles/` — keep design system files together
- Per-component CSS files with raw hex — use `var(--token)`
- Skipping `index.html`'s `data-theme` attribute — light/dark toggle becomes awkward
