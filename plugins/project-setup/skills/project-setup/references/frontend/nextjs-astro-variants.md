# Next.js and Astro variants

Vite + React is the default, but Next.js (SSR / app router) and Astro (content-heavy / mostly static) are first-class alternatives. Pick by circumstance.

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

## Next.js variant (apps/web/ if using app router)

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

Same isolation rule applies — backend secrets stay un-prefixed; never use `NEXT_PUBLIC_DATABASE_URL`.

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

The `/api/*` prefix convention still holds. Because `rewrites()` runs server-side, `BACKEND_URL` here can be a **server-only** var (no `NEXT_PUBLIC_` prefix) — unlike Vite, where any proxy target the browser depends on must be `VITE_*` and therefore public. See the Vite-vs-Next env-split comparison in `references/env-and-config/frontend-env-isolation.md`.

### `data-theme` SSR-safe

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

## Astro variant (apps/site/)

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

- `PUBLIC_*` exposed to client islands
- `import.meta.env.<VAR>` in `.astro` files runs at build time
- Server endpoints (`src/pages/api/*.ts` with `export const prerender = false`) have full env access

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

## Tokens / theming still works the same

`tokens.css` + `[data-theme="dark"]` is identical across all three frameworks. Tailwind config same. shadcn works in Next (officially supported); Astro can use shadcn React islands.

## Anti-patterns

- Using Next.js when you don't need SSR or RSC — overhead, complexity
- Using Astro when the whole site is dynamic — Vite is simpler
- Mixing frameworks in one app folder — split into separate apps in workspace
- `NEXT_PUBLIC_*` for things that should be server-only — leak
- Per-framework token files — share via `packages/styles` if multi-app
