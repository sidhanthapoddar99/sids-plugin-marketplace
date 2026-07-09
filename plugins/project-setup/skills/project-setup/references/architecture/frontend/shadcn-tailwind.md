# shadcn/ui + Tailwind

The default frontend component stack: shadcn primitives copied into `src/components/ui/`, styled via Tailwind classes that reference `var(--token)` aliases.

## Why shadcn (copy-not-import)

- Components are **copied into your repo**, not installed as a package
- Edit freely — fix a bug, change a behaviour, extend a prop
- Accessibility baseline from Radix primitives underneath
- Tailwind for styling — no CSS-in-JS runtime

The trade-off: every project gets its own version of `<Button>`; updates aren't automatic.

## Layout

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

In a multi-frontend workspace, `apps/<app>/src/components/ui/` becomes `packages/ui/src/`.

## Initial install

```bash
cd apps/frontend
bunx shadcn@latest init
```

Pick: TS, Tailwind, **CSS variables** (NOT inline values — we use our own tokens.css), base path `src/components/ui`.

Then per-component:

```bash
bunx shadcn@latest add button dialog input
```

## `components.json` (shadcn config)

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

## Tailwind config wired to tokens.css

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
      // agent-generated line wrong-by-assumption; restraint lives in the
      // project CLAUDE.md allowlist instead (see design-tokens.md,
      // "Typography — standard vocabulary, strict usage policy").
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

Brand classes (`bg-bg-2`, `text-fg-1`, `rounded-md`) resolve to `var(--token)`, which means **they auto-switch with theme**. Size and spacing classes (`text-base`, `p-4`) are stock Tailwind — standard values, theme-independent by design; which of them feature code may use is governed by the project CLAUDE.md allowlist (`styling-discipline.md` rule 4).

## shadcn defaults override

shadcn-generated components use Tailwind classes like `bg-background text-foreground`. Override the default mapping in your `tailwind.config.ts` or `globals.css` so those map to your tokens.

```css
/* src/styles/globals.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Map shadcn's expected names to our tokens */
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

This way shadcn's components Just Work without modification.

## Component example

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

- Hex values in `className` strings (`bg-[#fafafa]`) — defeats the system
- Bypassing the token alias (`tailwind.config.ts` colors as literals) — same
- Remapping stock scales in `theme.extend` (`fontSize: { sm: "13px" }`, custom `spacing`) — every agent-generated line becomes wrong-by-assumption; restraint belongs in the CLAUDE.md allowlist, not the vocabulary
- Per-component variants that reinvent variants already in shadcn
- Forgetting to update `components.json` when paths change
- Mixing shadcn with another component library (Material UI, Chakra) — pick one
