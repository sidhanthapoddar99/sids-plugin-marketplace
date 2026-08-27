# Frontend design tokens + theming setup — `tokens.css`, light/dark, shadcn wiring

Owns the **setup and wiring** of the frontend styling system: what `tokens.css` contains and where it lives, the light/dark `[data-theme]` mechanism and its toggle, and the shadcn + Tailwind config that consumes the tokens. This is the plumbing every app inherits.

The **feature-code usage discipline** — primitive-first composition, the typography usage allowlist, the enforcement greps — is L4 and owned by `references/4-feature/04_styling-discipline.md`. This file establishes the vocabulary; that file governs how feature code may use it.

## `tokens.css` — the single source of truth

Every **brand-specific** value — colors/surfaces, radii, materials (glass/blur), shadows, motion, font families — lives in **one CSS file** as CSS custom properties (`--bg-1`, `--radius-md`). Components consume them via `var(--token)` only. **No hex, no raw px in component CSS.**

Why `tokens.css` and not Tailwind config / SCSS vars / TS constants:

- **One file** — change a token, every component updates.
- **CSS-native** — works in any tool (component CSS, Tailwind config, inline styles, third-party widgets).
- **Theme switching is free** — re-declare on `[data-theme="dark"]` and every consumer adapts automatically.
- **Inspectable** — DevTools shows the resolved value at runtime.
- **No build step** — `tokens.css` is plain CSS.

### Location

| Layout | Path |
|---|---|
| Single frontend | `apps/frontend/src/styles/tokens.css` |
| Multiple frontends | `packages/styles/src/tokens.css` (consumed by all apps) |

In a multi-frontend workspace the styles package internals (what lives in `packages/styles`, its export surface) are owned by `references/3-app/05-package/00_shared-packages.md`.

### Token categories (default set)

```css
/* tokens.css */
:root {
  /* ─── Surfaces (grayscale base) ───────────────────────── */
  --bg-1: #ffffff;
  --bg-2: #fafafa;
  --bg-3: #f0f0f0;

  /* ─── Foreground ──────────────────────────────────────── */
  --fg-1: #0a0a0a;   /* primary text */
  --fg-2: #525252;   /* secondary text */
  --fg-3: #a3a3a3;   /* placeholder, disabled */

  /* ─── Borders ─────────────────────────────────────────── */
  --border-1: #e5e5e5;
  --border-2: #d4d4d4;

  /* ─── Accents (optional — keep palette small) ─────────── */
  --accent-1: #0070f3;
  --accent-2: #0051b3;

  /* ─── Status colors ───────────────────────────────────── */
  --success: #16a34a;
  --warning: #d97706;
  --danger:  #dc2626;
  --info:    #0284c7;

  /* ─── Glassmorphism (if used) ─────────────────────────── */
  --glass-1: rgba(255, 255, 255, 0.6);
  --glass-2: rgba(255, 255, 255, 0.4);
  --glass-3: rgba(255, 255, 255, 0.2);
  --blur-sm: 8px;
  --blur-md: 16px;
  --blur-lg: 32px;

  /* ─── Fonts (families ONLY — sizes, weights, line-heights,
     and spacing are Tailwind's stock scales, never tokens) ── */
  --font-family-base: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  --font-family-mono: "JetBrains Mono", "Fira Code", ui-monospace, monospace;

  /* ─── Spacing (non-Tailwind projects ONLY) ────────────── */
  /* Mirror the stock Tailwind scale verbatim — same numbering,
     same values (--space-N = N × 0.25rem; full stock block in the
     "Typography and spacing are NOT tokens" section below). Never
     retune. Tailwind projects use stock utilities (p-4, gap-6). */
  --space-2: 0.5rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --space-8: 2rem;

  /* ─── Border radius ──────────────────────────────────── */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-xl: 16px;
  --radius-pill: 9999px;

  /* ─── Shadows ────────────────────────────────────────── */
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.07);
  --shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);

  /* ─── Z-index ────────────────────────────────────────── */
  --z-base:    0;
  --z-overlay: 100;
  --z-modal:   200;
  --z-toast:   300;

  /* ─── Motion ─────────────────────────────────────────── */
  --duration-fast: 120ms;
  --duration-base: 240ms;
  --duration-slow: 400ms;
  --easing-standard: cubic-bezier(0.4, 0, 0.2, 1);
  --easing-emphasized: cubic-bezier(0.2, 0, 0, 1);
}
```

This default is intentional and conservative — modify per project, but stay within the category structure.

### Component CSS rule

```css
/* ✅ — uses tokens */
.card {
  background: var(--bg-2);
  color: var(--fg-1);
  padding: var(--space-4);
  border: 1px solid var(--border-1);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
  transition: background var(--duration-fast) var(--easing-standard);
}

/* ❌ — uses raw values */
.card {
  background: #fafafa;
  padding: 16px;
  border-radius: 8px;
}
```

**Lint rule** (biome or custom): forbid hex and raw px in `src/components/**/*.css`. Allowed only in `src/styles/tokens.css` (and the dark-mode block). (`**` here is a lint-config glob the tool expands itself; shell-command checks use the shell-proof `grep -r --include` form owned by `references/4-feature/04_styling-discipline.md`.) The full feature-code enforcement greps are owned by `styling-discipline.md`.

## Typography and spacing are NOT tokens

Type sizes, font weights, spacing, and container widths are deliberately **not** tokens: they use Tailwind's stock scales, **untouched**. `tokens.css` owns only what is genuinely brand-specific (colors/surfaces, radii, materials, shadows, motion, font families).

The wiring rule: **never remap standard scale names to custom values, never invent custom size utilities** in `tokens.css` or `tailwind.config.ts`. Agents' training data assumes `text-sm` = 14px/1.43; remapping it makes every generated line subtly wrong-by-assumption, and a custom name (`type-md`) is a token no model has seen. Keep the vocabulary stock so the wiring stays a contract every generated line can rely on.

These are the stock values a project's stylesheet must resolve to (Tailwind's default theme). In a Tailwind project they already exist — ship them untouched. **Non-Tailwind projects declare exactly this block** (same names, same values, never retuned) and consume it from plain CSS:

```css
/* Type scale (size + paired line-height) */
--text-xs: .75rem;      --text-xs--line-height: calc(1 / .75);
--text-sm: .875rem;     --text-sm--line-height: calc(1.25 / .875);
--text-base: 1rem;      --text-base--line-height: calc(1.5 / 1);
--text-lg: 1.125rem;    --text-lg--line-height: calc(1.75 / 1.125);
--text-xl: 1.25rem;     --text-xl--line-height: calc(1.75 / 1.25);
--text-2xl: 1.5rem;     --text-2xl--line-height: calc(2 / 1.5);
--text-3xl: 1.875rem;   --text-3xl--line-height: calc(2.25 / 1.875);
--text-4xl: 2.25rem;    --text-4xl--line-height: calc(2.5 / 2.25);
--text-5xl: 3rem;       --text-5xl--line-height: 1;
--text-6xl: 3.75rem;    --text-6xl--line-height: 1;
--text-7xl: 4.5rem;     --text-7xl--line-height: 1;
--text-8xl: 6rem;       --text-8xl--line-height: 1;
--text-9xl: 8rem;       --text-9xl--line-height: 1;

/* Weights */
--font-weight-light: 300;
--font-weight-normal: 400;
--font-weight-medium: 500;
--font-weight-semibold: 600;
--font-weight-bold: 700;
--font-weight-extrabold: 800;

/* Spacing (linear: p-N = N × --spacing) + containers */
--spacing: .25rem;
--breakpoint-2xl: 96rem;
--container-xs: 20rem;   --container-sm: 24rem;   --container-md: 28rem;
--container-lg: 32rem;   --container-xl: 36rem;   --container-2xl: 42rem;
--container-3xl: 48rem;  --container-4xl: 56rem;  --container-5xl: 64rem;
--container-6xl: 72rem;
```

**Which of these sizes/weights feature code may actually use** — the per-project allowlist and its anti-patterns — is a **usage** decision owned by `references/4-feature/04_styling-discipline.md` and declared in the project's CLAUDE.md. Do not restate it here; the vocabulary is set up here, the restraint is applied there.

## Dark mode

In a separate stylesheet or below the `:root` block, redeclare only the tokens that change:

```css
[data-theme="dark"] {
  --bg-1: #0a0a0a;
  --bg-2: #1a1a1a;
  --bg-3: #2a2a2a;

  --fg-1: #fafafa;
  --fg-2: #a3a3a3;
  --fg-3: #525252;

  --border-1: #2a2a2a;
  --border-2: #404040;

  --glass-1: rgba(0, 0, 0, 0.6);
  --glass-2: rgba(0, 0, 0, 0.4);
  --glass-3: rgba(0, 0, 0, 0.2);

  /* spacing, radii, fonts stay the same */
}
```

Every component that reads `var(--bg-1)` / `var(--fg-1)` flips automatically when `data-theme` changes. The toggle mechanism follows.

## Light + dark via `[data-theme="dark"]` on `<html>`

The default theme convention. Both modes always present unless the project is marketing-only (see exception below).

### Mechanism

`<html data-theme="light">` is the default. Tokens redefined under `[data-theme="dark"]` override `:root`.

```html
<html lang="en" data-theme="light">
  <body><div id="root"></div></body>
</html>
```

### Toggling

```tsx
// apps/frontend/src/context/theme.tsx
import { createContext, useContext, useEffect, useState } from "react";

type Theme = "light" | "dark";
const ThemeContext = createContext<{ theme: Theme; setTheme: (t: Theme) => void } | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => {
    if (typeof window === "undefined") return "light";
    const saved = localStorage.getItem("theme") as Theme | null;
    if (saved) return saved;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  });

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("theme", theme);
  }, [theme]);

  return <ThemeContext.Provider value={{ theme, setTheme }}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme outside ThemeProvider");
  return ctx;
}
```

In a multi-app workspace, share ONE toggle implementation (e.g. via `packages/hooks`) — never diverge the mechanism per app.

### Why `data-theme` not `class="dark"`?

- More explicit ("dark" feels boolean; `data-theme` extends to `high-contrast`, `sepia`, etc.).
- Easier to query (`[data-theme="dark"]`) than `:has(.dark)` or `:where(.dark, .dark *)`.
- Tailwind supports it via the `dark:` variant configured with `darkMode: ["selector", '[data-theme="dark"]']` (see the Tailwind config below).

### SSR / initial flash

For SSR frameworks (Next, Astro), avoid flash-of-unstyled-content by setting `data-theme` in a **blocking inline script** in `<head>`, before any style or script and before the framework mounts:

```html
<script>
  (function() {
    var saved = localStorage.getItem("theme");
    var prefers = window.matchMedia("(prefers-color-scheme: dark)").matches;
    var theme = saved || (prefers ? "dark" : "light");
    document.documentElement.dataset.theme = theme;
  })();
</script>
```

The dataset is set before paint. Setting `data-theme` via `useEffect` **only** causes a flash on first paint — do the blocking script too. Framework-specific placement (Next `layout.tsx`, Astro layout) is owned by `references/3-app/03-web-app/01_framework-variants.md`.

### Marketing-only exception

Marketing / landing pages may be light-only when: the design demands it (gradient hero, brand consistency), users won't spend long-form time on the page, and the brand explicitly doesn't use dark mode. Even then, app pages (signed-in, dashboards) keep both modes. Don't mix within the app.

## shadcn/ui + Tailwind

The default frontend component stack: shadcn primitives copied into `src/components/ui/`, styled via Tailwind classes that reference `var(--token)` aliases.

### Why shadcn (copy-not-import)

- Components are **copied into your repo**, not installed as a package — edit freely (fix a bug, change behaviour, extend a prop).
- Accessibility baseline from Radix primitives underneath.
- Tailwind for styling — no CSS-in-JS runtime.

Trade-off: every project gets its own `<Button>`; updates aren't automatic.

### Layout

```
apps/frontend/src/components/
├── ui/                          # shadcn primitives + project wrappers
│   ├── button.tsx
│   ├── dialog.tsx
│   ├── input.tsx
│   ├── tooltip.tsx
│   └── …
└── layout/                      # app shell (sidebar, navbar)
    └── …
```

In a multi-frontend workspace, `apps/<app>/src/components/ui/` becomes `packages/ui/src/` — the package internals (~15-component grouping, export surface) are owned by `references/3-app/05-package/00_shared-packages.md`.

### Initial install

```bash
cd apps/frontend
bunx shadcn@latest init
```

Pick: TS, Tailwind, **CSS variables** (NOT inline values — we use our own `tokens.css`), base path `src/components/ui`. Then per-component:

```bash
bunx shadcn@latest add button dialog input
```

### `components.json`

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "tailwind.config.ts",
    "css": "src/styles/globals.css",
    "baseColor": "neutral",
    "cssVariables": true
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui",
    "lib": "@/lib",
    "hooks": "@/hooks"
  }
}
```

### Tailwind config wired to `tokens.css`

```ts
// tailwind.config.ts
import type { Config } from "tailwindcss";

export default {
  darkMode: ["selector", '[data-theme="dark"]'],
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      // Brand tokens ONLY. fontSize, fontWeight, spacing, and containers are
      // deliberately ABSENT — the stock Tailwind scales ship untouched.
      // Remapping standard names (e.g. fontSize.sm → 13px) makes every
      // agent-generated line wrong-by-assumption; the usage allowlist lives
      // in project CLAUDE.md (see references/4-feature/04_styling-discipline.md).
      colors: {
        bg: { 1: "var(--bg-1)", 2: "var(--bg-2)", 3: "var(--bg-3)" },
        fg: { 1: "var(--fg-1)", 2: "var(--fg-2)", 3: "var(--fg-3)" },
        border: { 1: "var(--border-1)", 2: "var(--border-2)" },
        accent: { 1: "var(--accent-1)", 2: "var(--accent-2)" },
        success: "var(--success)",
        warning: "var(--warning)",
        danger: "var(--danger)",
      },
      borderRadius: {
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
        lg: "var(--radius-lg)",
        xl: "var(--radius-xl)",
      },
    },
  },
} satisfies Config;
```

Brand classes (`bg-bg-2`, `text-fg-1`, `rounded-md`) resolve to `var(--token)`, so they **auto-switch with theme**. Size and spacing classes (`text-base`, `p-4`) are stock Tailwind — standard values, theme-independent by design.

### shadcn defaults override

shadcn-generated components use Tailwind classes like `bg-background text-foreground`. Map those expected names to your tokens in `globals.css` so they Just Work:

```css
/* src/styles/globals.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: var(--bg-1);
    --foreground: var(--fg-1);
    --muted: var(--bg-2);
    --muted-foreground: var(--fg-2);
    --border: var(--border-1);
    --input: var(--border-1);
    --primary: var(--accent-1);
    --primary-foreground: var(--bg-1);
    --radius: var(--radius-md);
  }
}
```

### Component example

```tsx
// src/components/ui/button.tsx (shadcn-generated, edited)
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center rounded-md text-base transition-colors",
  {
    variants: {
      variant: {
        default: "bg-accent-1 text-fg-1 hover:bg-accent-2",
        outline: "border border-border-1 bg-transparent hover:bg-bg-2",
        ghost: "hover:bg-bg-2",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-8 px-3",
        lg: "h-12 px-6",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export function Button({ className, variant, size, ...props }: ButtonProps) {
  return <button className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}
```

All tokens consumed via Tailwind classes → CSS vars → flips with `data-theme`.

## Anti-patterns

- Hex / px in component CSS, or hex values in `className` strings (`bg-[#fafafa]`) — defeats the token system.
- Bypassing the token alias (Tailwind `colors` as literals) — same.
- Remapping stock scales in `tokens.css` or `theme.extend` (`fontSize: { sm: "13px" }`, custom `spacing`) — every agent-generated line becomes wrong-by-assumption; the restraint belongs in the CLAUDE.md allowlist, not the vocabulary.
- Hard-coding `prefers-color-scheme` checks in components — theme switching is the `[data-theme]` attribute's job; components just consume tokens.
- Per-component "design tokens" files — collapses into many sources of truth.
- Renaming tokens frequently — every consumer breaks.
- Adding a token for one-off use — that's a magic number with a name; inline it.
- Skipping the `:root` declarations and only doing dark — light is the default; both must exist.
- Per-framework or per-app token files — share via `packages/styles` if multi-app.
- Different theme-toggle mechanisms per app in a workspace, or `class="dark"` and `data-theme="dark"` both in use — pick one, share it.
- Setting `data-theme` via `useEffect` only in SSR frameworks — flashes on first paint; add the blocking pre-mount script.
- Forgetting to persist the user's theme choice — they re-toggle every page load.
- Per-component variants that reinvent variants already in shadcn; mixing shadcn with another component library (Material UI, Chakra) — pick one.

## See also

- `references/4-feature/04_styling-discipline.md` — the feature-code usage discipline this vocabulary feeds: primitive-first rules, the typography usage allowlist, enforcement greps, the CLAUDE.md precedence block.
- `references/3-app/05-package/00_shared-packages.md` — `packages/styles` and `packages/ui` internals when multiple frontends share the tokens + primitives.
- `references/3-app/03-web-app/01_framework-variants.md` — how Next/Astro apply the `data-theme` + SSR-flash mechanism.
- `references/3-app/03-web-app/00_app-skeleton.md` — where `src/styles/` and `src/components/ui/` sit in the frontend skeleton.
- `references/3-app/00_index.md` — the app-level charter this reference serves.
