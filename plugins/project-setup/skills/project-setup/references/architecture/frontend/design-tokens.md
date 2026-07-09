# Design tokens — `tokens.css` as the single source of truth

Every **brand-specific** value — colors/surfaces, radii, materials (glass/blur), shadows, motion, font families — lives in **one CSS file** as CSS custom properties (`--bg-1`, `--radius-md`). Components consume them via `var(--token)` only. **No hex, no raw px in component CSS.**

Type sizes, font weights, spacing, and container widths are deliberately **not** tokens: those use Tailwind's stock scales, untouched. See "Typography — standard vocabulary, strict usage policy" below.

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

  /* ─── Fonts (families ONLY — sizes, weights, line-heights,
     and spacing are Tailwind's stock scales, never tokens) ── */
  --font-family-base: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  --font-family-mono: "JetBrains Mono", "Fira Code", ui-monospace, monospace;

  /* ─── Spacing (non-Tailwind projects ONLY) ────────────── */
  /* Mirror the stock Tailwind scale verbatim — same numbering,
     same values (--space-N = N × 0.25rem; full stock block in the
     Typography section below). Never retune. Tailwind projects
     use stock utilities (p-4, gap-6) instead. */
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

## Typography — standard vocabulary, strict usage policy

Typography splits into two layers, and it matters which layer each rule lives in.

### Vocabulary layer — ship Tailwind's stock theme untouched

The full default type scale (`text-xs` … `text-7xl`, with stock line-heights), the full weight set (`font-light` … `font-extrabold`), stock spacing and container scales. **Do not remap standard names to custom values. Do not create custom size utilities.**

Why: agents' training data assumes `text-sm` = 14px/1.43. Remap `text-sm` to 13px and every generated line is subtly **wrong-by-assumption** — spacing math, icon pairing, optical judgments all inherit the error invisibly. And a custom vocabulary (`type-md`) is a token no model has ever seen; it gets forgotten mid-file. `tokens.css` owns only what is genuinely brand-specific: colors/surfaces, radii, materials, shadows, motion, font families.

These are the stock values — the contract every generated line assumes. They come from Tailwind's default theme; a project's stylesheet must resolve them to exactly this:

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

In a Tailwind project these already exist — ship the default theme and don't touch them. Non-Tailwind projects declare exactly this block (same names, same values, never retuned) and consume it from plain CSS.

### Policy layer — a small per-project allowlist. ALL restraint lives here.

Each project declares in its CLAUDE.md which sizes and weights feature code may use. The default allowlist:

- **`text-sm`** — ~90% of the UI: all content (tables, controls, labels, descriptions)
- **`text-base`** — headings (card/section titles, top-bar title). The only heading size.
- **`text-xs`** — sparingly: badges, timestamps, fine meta
- **`font-normal`** everywhere; **`font-medium` OR `font-semibold`** (pick ONE per project) as the single rare emphasis, applied only inside ui-package primitives. Hierarchy comes from **size and foreground color, never weight**.

Every other size and weight **exists but is banned in feature code** — banned, not deleted. They are reserved for hero surfaces (landing pages, empty states, marketing) via ui-package primitives created in an explicit design pass (`styling-discipline.md` rule 6).

**Why restraint lives in policy, not vocabulary:** a policy change ("allow `text-lg` for page titles") is a one-line CLAUDE.md edit plus a grep sweep. A vocabulary change (retuning custom token values) is a migration across every consumer. Restraint must live in the cheap layer.

### Anti-patterns — the old approaches, named

- **(a) Remapping standard utility names** to non-standard values (`text-sm` → 13px) — every agent-generated line becomes wrong-by-assumption
- **(b) Inventing custom size vocabularies** (`type-md`, `--text-heading`) — tokens no model has seen
- **(c) Size×weight rungs** (`xl=28/700, lg=20/600, base=15/500…`) — pairs each size with its own weight, silently manufacturing three-plus effective weights while every line looks compliant. Sizes never carry weights.

Enforcement greps live in `styling-discipline.md`; the per-project allowlist lives in the CLAUDE.md template block.

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

- atheneum's `frontend/src/styles/tokens.css` — close to this template for colors/surfaces/glass (its custom font sizes predate the stock-scale policy; don't copy those)
- plane's `packages/ui/styles/` — multi-frontend variant

## Anti-patterns

- Hex / px in component CSS — defeats the system
- Remapping standard scale names to custom values, or inventing custom size vocabularies — makes agent output wrong-by-assumption (see Typography section)
- Size×weight rungs (`xl=28/700, lg=20/600`) — pairs each size with its own weight, silently creating 3+ effective weights; sizes never carry weights
- Per-component "design tokens" files — collapses into many sources of truth
- Renaming tokens frequently — every consumer breaks
- Adding a token for one-off use — that's a magic number with a name; just inline
- Skipping the `:root` declarations and only doing dark — light is the default; both must exist
