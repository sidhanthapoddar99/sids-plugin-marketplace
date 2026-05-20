# Light + dark via `[data-theme="dark"]` on `<html>`

The default theme convention. Both modes always present unless the project is marketing-only (in which case light-only is acceptable).

## Mechanism

`<html data-theme="light">` is the default. Tokens redefined under `[data-theme="dark"]` override `:root`.

```css
/* tokens.css */
:root {
  --bg-1: #ffffff;
  --fg-1: #0a0a0a;
}

[data-theme="dark"] {
  --bg-1: #0a0a0a;
  --fg-1: #fafafa;
}
```

```html
<html lang="en" data-theme="light">
  <body><div id="root"></div></body>
</html>
```

Every component that uses `var(--bg-1)` / `var(--fg-1)` flips automatically when `data-theme` changes.

## Toggling

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

## Why `data-theme` not `class="dark"`?

- More explicit ("dark" feels boolean; "data-theme" extends to "high-contrast", "sepia", etc.)
- Easier to query (`[data-theme="dark"]`) than `:has(.dark)` or `:where(.dark, .dark *)`
- Tailwind supports it via `dark:` variant configured with `darkMode: ["selector", '[data-theme="dark"]']`

## Tailwind integration

```ts
// tailwind.config.ts
export default {
  darkMode: ["selector", '[data-theme="dark"]'],
  // ...
};
```

Tailwind `dark:bg-bg-1` now works under `data-theme="dark"`.

## SSR / initial flash

For SSR frameworks (Next, Astro), avoid flash-of-unstyled-content by setting `data-theme` in a blocking inline script before React mounts:

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

Place this in `<head>` before any style or script. The dataset is set before paint.

## Marketing-only exception

Marketing / landing pages can be light-only when:

- The design demands it (gradient hero, brand consistency)
- Users won't spend long-form time on the page
- The brand explicitly doesn't use dark mode

Even then, app pages (signed-in, dashboards) keep both modes. Don't mix within the app.

## Anti-patterns

- Different toggle mechanisms per app in a workspace — pick one, share via `packages/hooks`
- `class="dark"` and `data-theme="dark"` both in use — pick one
- Setting `data-theme` via `useEffect` only — causes flash on first paint; do it in a blocking pre-mount script too
- Hard-coding `prefers-color-scheme: dark` checks in components — they should just consume tokens
- Forgetting to persist user choice — they re-toggle every page load
