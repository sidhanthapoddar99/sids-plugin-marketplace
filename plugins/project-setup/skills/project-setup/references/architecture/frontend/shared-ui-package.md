# `packages/ui` — the shared UI package

When two or more frontends need the same components, extract to `packages/ui` (or several smaller packages). Single source of truth for visual elements.

## What lives in `packages/ui`

- **Primitives** — shadcn-generated components (Button, Dialog, Input, etc.)
- **Project-specific wrappers** — `<AppButton>` that wraps shadcn's `<Button>` with sensible defaults
- **Layout primitives** — `<Stack>`, `<Inline>`, `<Card>` if you have a custom layout system
- **Icons re-exports** — wrap lucide-react / phosphor / your icon set so every app uses the same set

## What does NOT live there

- **Business logic** — that's app-level or `packages/services`
- **Routing** — apps own their routes
- **State** — UI is presentational; state lives in apps or `packages/hooks`
- **API calls** — those go in `packages/services`

## Layout

```
packages/ui/
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts                 # barrel — re-exports all primitives
    ├── button.tsx
    ├── dialog.tsx
    ├── input.tsx
    ├── icons.tsx
    ├── theme-toggle.tsx
    └── …
```

`src/index.ts` re-exports everything for `import { Button } from "@my/ui"`. Apps can also deep-import for tree-shaking: `import { Button } from "@my/ui/button"`.

## Separate packages for orthogonal concerns

Better than one mega-package:

| Package | Contents |
|---|---|
| `packages/ui` | Visual primitives |
| `packages/styles` | tokens.css, globals.css, light/dark |
| `packages/tailwind-config` | shared tailwind preset |
| `packages/typescript-config` | base tsconfig.json |
| `packages/eslint-config` (or biome) | shared lint rules |
| `packages/hooks` | reusable hooks (useDebounce, useMediaQuery) |
| `packages/services` | API clients (typed fetch wrappers) |
| `packages/types` | TS types shared between frontends + types codegen'd from backend |
| `packages/utils` | pure helpers — date formatting, string utilities |

Plane's 15 packages are an example. Don't force the split; let it grow as patterns repeat.

## Consuming in an app

```json
// apps/web/package.json
{
  "dependencies": {
    "@my/ui": "workspace:*",
    "@my/styles": "workspace:*",
    "@my/hooks": "workspace:*",
    "@my/services": "workspace:*",
    "react": "catalog:"
  }
}
```

```tsx
// apps/web/src/App.tsx
import { Button } from "@my/ui/button";
import { useAuth } from "@my/hooks";
import { useUsersQuery } from "@my/services";
import "@my/styles/tokens.css";
import "@my/styles/globals.css";
```

## Shared `tailwind-config`

```ts
// packages/tailwind-config/index.ts
import type { Config } from "tailwindcss";

const sharedConfig: Omit<Config, "content"> = {
  theme: {
    extend: {
      // Brand tokens only — fontSize/fontWeight/spacing stay stock
      // (never remapped; see design-tokens.md typography policy)
      colors: {
        // map to CSS vars set by tokens.css
        bg: { 1: "var(--bg-1)", 2: "var(--bg-2)", 3: "var(--bg-3)" },
        fg: { 1: "var(--fg-1)", 2: "var(--fg-2)", 3: "var(--fg-3)" },
      },
      borderRadius: {
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
      },
    },
  },
};

export default sharedConfig;
```

```ts
// apps/web/tailwind.config.ts
import shared from "@my/tailwind-config";

export default {
  ...shared,
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
};
```

Tokens live in CSS (consumable from any tool); Tailwind classes alias to those tokens.

## Anti-patterns

- One mega `packages/shared` containing everything — split by concern
- Importing app-specific code into a package — packages depend down, not up
- Per-app duplication of the same component — extract on third use
- Forgetting `workspace:*` in dependencies (using a real version like `0.0.1`) — pnpm warns; fix
- Packages that pull in heavy deps consumed by only one app — keep packages slim
