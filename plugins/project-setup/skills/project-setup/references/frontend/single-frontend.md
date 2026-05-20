# Single frontend — Topology 02 / 03

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
│   ├── App.tsx                  # top-level component
│   ├── styles/
│   │   ├── tokens.css           # design tokens
│   │   ├── globals.css          # body, root, base resets
│   │   └── elements.css         # base element overrides
│   ├── components/
│   │   ├── ui/                  # shadcn primitives + project wrappers
│   │   └── layout/              # navigation, page chrome
│   ├── lib/
│   │   ├── api.ts               # fetch wrapper
│   │   ├── utils.ts
│   │   └── ...
│   ├── hooks/                   # reusable hooks
│   ├── pages/ (or routes/)      # top-level routes
│   └── context/                 # React context providers
├── Dockerfile
└── nginx/                       # optional — bundle nginx config for prod stage
    └── nginx.conf
```

## What's in each subfolder

| Folder | Contents |
|---|---|
| `src/styles/` | All CSS. `tokens.css` is the only place hex/px live; everything else uses `var(--token)`. |
| `src/components/ui/` | shadcn-generated primitives. Edit freely (shadcn is copy-not-import). |
| `src/components/layout/` | App shell — navbar, sidebar, page wrapper. |
| `src/components/<feature>/` | Feature-grouped components. Folders by feature, not by kind. |
| `src/lib/` | Cross-cutting helpers — API client, utils, formatters. |
| `src/hooks/` | Reusable hooks. |
| `src/pages/` (or `routes/`) | Per-route components. Routing config typically in `App.tsx` or `routes.tsx`. |
| `src/context/` | React Context providers (Auth, Theme, etc.). |

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
| Second frontend that shares any code | Migrate to Topology 04 (`packages/ui`, `packages/styles`) |
| Server-rendering required | Switch to Next.js or Astro variants |
| PWA / offline mode | Add `vite-plugin-pwa` + Workbox |
| Heavy state | Add Zustand (local) + TanStack Query (server) |
| Forms | Add React Hook Form + Zod |

## Anti-patterns

- `src/` at repo root, not under `apps/frontend/` — see `src` rule in summary.md
- Component files past 500 lines — split
- Putting `tokens.css` outside `src/styles/` — keep design system files together
- Per-component CSS files with raw hex — use `var(--token)`
- Skipping `index.html`'s `data-theme` attribute — light/dark toggle becomes awkward
