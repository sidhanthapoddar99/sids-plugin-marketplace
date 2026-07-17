# Frontend framework variants — Next.js and Astro

Vite + React is the default frontend framework (owned by `references/3-app/frontend/app-skeleton.md`). This file owns the two first-class alternatives — **Next.js** (SSR / app router) and **Astro** (content-heavy / mostly static) — the per-framework tree, env split, dev proxy, and `data-theme` application. Pick by circumstance.

## Picking guide

| Scenario | Pick |
|---|---|
| Dashboard / SPA, no SEO concerns | **Vite + React** |
| User-generated content with SEO (Reddit-like) | **Next.js** |
| Marketing site / blog / docs | **Astro** |
| Mix — public marketing + private app | **Astro** (marketing) + **Vite** (app), separate apps in workspace |
| Mostly static with islands | **Astro** |
| Requires React Server Components | **Next.js** |
| Hate boilerplate, single SPA | **Vite** |

## Next.js variant (`apps/web/` if using app router)

```
apps/web/
├── package.json
├── .env / .env.example          # NEXT_PUBLIC_* + server-only vars
├── next.config.mjs
├── tsconfig.json
├── tailwind.config.ts
├── postcss.config.cjs
├── public/
├── src/
│   ├── app/                     # app router
│   │   ├── layout.tsx           # sets <html data-theme="…">
│   │   ├── page.tsx
│   │   ├── api/                 # route handlers if needed
│   │   │   └── …
│   │   └── (auth)/              # route groups
│   ├── components/
│   ├── lib/
│   └── styles/
│       ├── tokens.css
│       ├── globals.css
│       └── light-dark.css
└── Dockerfile
```

### Env split

| Var prefix | Scope |
|---|---|
| `NEXT_PUBLIC_*` | Baked into client bundle |
| (no prefix) | Server-only, available in server components + API routes |

The same isolation rule applies — backend secrets stay un-prefixed; never `NEXT_PUBLIC_DATABASE_URL`. The full public-var leak doctrine is owned by `references/2-repo/env-and-config/frontend-env-isolation.md`.

### Dev proxy

Next.js has built-in API routes (`src/app/api/*`) that can forward to a backend, OR use `next.config.mjs#rewrites`:

```js
// next.config.mjs
export default {
  async rewrites() {
    return [
      { source: "/api/:path*", destination: `${process.env.BACKEND_URL}/api/:path*` },
    ];
  },
};
```

The `/api/*` prefix convention still holds (routing contract owned by `references/2-repo/deployment/proxy-and-exposure.md`). Because `rewrites()` runs server-side, `BACKEND_URL` here can be a **server-only** var (no `NEXT_PUBLIC_` prefix) — unlike Vite, where any proxy target the browser depends on must be `VITE_*` and therefore public. See the Vite-vs-Next env-split comparison in `references/2-repo/env-and-config/frontend-env-isolation.md`.

### `data-theme` SSR-safe

The `data-theme` mechanism and the blocking-script rationale are owned by `references/3-app/frontend/tokens-setup.md`; Next applies it in the root layout:

```tsx
// src/app/layout.tsx
import "@/styles/tokens.css";
import "@/styles/globals.css";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                var s = localStorage.getItem("theme");
                var p = window.matchMedia("(prefers-color-scheme: dark)").matches;
                document.documentElement.dataset.theme = s || (p ? "dark" : "light");
              })();
            `,
          }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
```

`suppressHydrationWarning` because the script mutates the DOM before React hydrates.

## Astro variant (`apps/site/`)

```
apps/site/
├── package.json
├── astro.config.mjs
├── tsconfig.json
├── tailwind.config.ts
├── public/
├── src/
│   ├── pages/                   # .astro / .md / .mdx files become routes
│   │   ├── index.astro
│   │   ├── about.astro
│   │   └── blog/[slug].astro
│   ├── layouts/
│   │   └── Base.astro
│   ├── components/
│   ├── content/                 # content collections (Astro >=2)
│   │   └── blog/
│   │       └── …md
│   └── styles/
│       ├── tokens.css
│       ├── globals.css
│       └── light-dark.css
└── Dockerfile                   # builds to /dist/, served by nginx
```

### Astro env

- `PUBLIC_*` exposed to client islands.
- `import.meta.env.<VAR>` in `.astro` files runs at build time.
- Server endpoints (`src/pages/api/*.ts` with `export const prerender = false`) have full env access.

### When to use islands

Astro defaults to **static**. Sprinkle React (or Svelte, Vue) only where interactivity is needed:

```astro
---
import Counter from "@/components/Counter.tsx";
---
<html data-theme="light">
  <body>
    <h1>Static content</h1>
    <Counter client:load />     <!-- React island -->
  </body>
</html>
```

`client:load` / `client:idle` / `client:visible` control when the island hydrates. Most marketing pages need none.

## Tokens / theming still work the same

`tokens.css` + `[data-theme="dark"]` is identical across all three frameworks; the Tailwind config is the same. shadcn works in Next (officially supported); Astro can use shadcn React islands. All of this — the token vocabulary, the theme toggle, the shadcn wiring — is owned by `references/3-app/frontend/tokens-setup.md`. In a multi-app workspace, share the tokens via `packages/styles` rather than per-framework token files.

## Anti-patterns

- Using Next.js when you don't need SSR or RSC — overhead, complexity.
- Using Astro when the whole site is dynamic — Vite is simpler.
- Mixing frameworks in one app folder — split into separate apps in the workspace.
- `NEXT_PUBLIC_*` / `PUBLIC_*` for things that should be server-only — leak.
- Per-framework token files — share via `packages/styles` if multi-app.

## See also

- `references/3-app/frontend/app-skeleton.md` — the default Vite + React skeleton and the frontend structure decision this branches off.
- `references/3-app/frontend/tokens-setup.md` — the token vocabulary, `data-theme` mechanism, and shadcn wiring reused across all three frameworks.
- `references/2-repo/env-and-config/frontend-env-isolation.md` — the `VITE_*` / `NEXT_PUBLIC_*` / `PUBLIC_*` public-var leak doctrine.
- `references/2-repo/deployment/proxy-and-exposure.md` — the `/api/*` routing contract and Vite-proxy ↔ nginx pair.
- `references/3-app/frontend/workspaces-mechanics.md` — running marketing + app frameworks as separate apps in one workspace.
- `references/3-app/00_charter.md` — the app-level charter this reference serves.
