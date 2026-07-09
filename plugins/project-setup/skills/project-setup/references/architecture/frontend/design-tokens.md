# Design tokens — `tokens.css` as the single source of truth

Every color, spacing, radius, font-size, blur, shadow lives in **one CSS file** as CSS custom properties (`--bg-1`, `--space-4`, `--radius-md`). Components consume them via `var(--token)` only. **No hex, no raw px in component CSS.**

## Why tokens.css and not Tailwind / SCSS vars / TS constants?

- **One file** — change a token, every component updates
- **CSS-native** — works in any tool (component CSS, Tailwind config, inline styles, third-party widgets)
- **Theme switching is free** — re-declare on `[data-theme="dark"]` and every consumer adapts automatically
- **Inspectable** — DevTools shows the resolved value at runtime
- **No build step** — tokens.css is plain CSS

## Location

| Layout | Path |
|---|---|
| 02, single frontend | `apps/frontend/src/styles/tokens.css` |
| 02, multiple frontends | `packages/styles/src/tokens.css` (consumed by all apps) |

## Token categories (default set)

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

  /* ─── Typography ──────────────────────────────────────── */
  --text-sm:   13px;
  --text-base: 15px;
  --text-lg:   18px;
  --text-xl:   22px;
  --weight-regular: 400;   /* THE weight — used everywhere */
  --weight-emphasis: 600;  /* exists for the rare absolutely-required case; not part of the ladder */
  --leading-tight:  1.2;
  --leading-normal: 1.5;
  --leading-loose:  1.75;
  --font-family-base: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  --font-family-mono: "JetBrains Mono", "Fira Code", ui-monospace, monospace;

  /* ─── Spacing (8px base scale) ───────────────────────── */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 24px;
  --space-6: 32px;
  --space-7: 48px;
  --space-8: 64px;

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

## Dark mode

In a separate stylesheet or below the `:root` block:

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

See `light-dark-data-attr.md` for the toggle mechanism.

## Four font sizes, two weights — firm

**Exactly FOUR text sizes and exactly TWO weights.** This is the standard, not a suggestion. Default values — 13 / 15 / 18 / 22 px (`sm / base / lg / xl`); pixel values and utility naming may vary per project, the counts may not.

- The **common weight** (`--weight-regular`, 400) is used throughout — **headings included**. Hierarchy comes from **size and foreground color, never weight**.
- The **emphasis weight** (`--weight-emphasis`, 600) is for the rare case something must read bolder: one dedicated utility, applied only inside ui-package primitives, sparingly.
- The ladder is closed: one largest-size anchor per screen (page title or app chrome — the project decides and records it), `lg` for section/card titles, `base` for body and controls, `sm` for table cells / labels / meta.

**ANTI-PATTERN — size×weight rungs.** Do not pair each size with its own weight (`xl=28/700, lg=20/600, base=15/500…`). That silently manufactures three-plus effective weights while every line looks compliant, and defeats the uniformity the two-weight rule exists for. Sizes never carry weights.

```css
.page-title {
  font-size: var(--text-xl);
  color: var(--fg-1);
}
.section-title {
  font-size: var(--text-lg);
  color: var(--fg-1);
}
.body {
  font-size: var(--text-base);
  color: var(--fg-1);
}
.caption {
  font-size: var(--text-sm);
  color: var(--fg-2);
}
```

Utility naming and pixel values adapt per project; the 4-size / 2-weight structure does not. Enforcement rules live in `styling-discipline.md`.

## Component CSS rule

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

**Lint rule** (biome or custom): forbid hex and raw px in `src/components/**/*.css`. Allowed only in `src/styles/tokens.css` (and dark.css). (`**` here is a lint-config glob, which the tool expands itself; if you implement the check as a shell command instead, use the shell-proof `grep -r --include` form from `styling-discipline.md` — shell `**` silently under-recurses in default bash.)

## Real-world reference

- atheneum's `frontend/src/styles/tokens.css` — close to this template; grayscale + glassmorphism, three font sizes
- plane's `packages/ui/styles/` — multi-frontend variant

## Anti-patterns

- Hex / px in component CSS — defeats the system
- Size×weight rungs (`xl=28/700, lg=20/600`) — pairs each size with its own weight, silently creating 3+ effective weights; sizes never carry weights
- Per-component "design tokens" files — collapses into many sources of truth
- Renaming tokens frequently — every consumer breaks
- Adding a token for one-off use — that's a magic number with a name; just inline
- Skipping the `:root` declarations and only doing dark — light is the default; both must exist
