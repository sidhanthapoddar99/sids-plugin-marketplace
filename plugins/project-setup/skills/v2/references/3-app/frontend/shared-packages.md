# Shared frontend packages — internals

Owns what lives **inside** a workspace `packages/*` folder: what each package contains and excludes, the single export surface every package presents, the split into orthogonal packages, tailwind-config wiring, and **tripwire T4** (flat components in a ui package). Package *placement* (which scope a package sits at) is owned by `references/2-repo/grouping-topology.md`; workspace *config bodies* by `references/3-app/frontend/workspaces-mechanics.md`; this file is what goes below `packages/<pkg>/src/`.

Packages are read by *more* people than app code, so navigability matters more, not less — they carry the same skeleton discipline and the same caps as an app.

## What lives in `packages/ui`

- **Primitives** — shadcn-generated components (Button, Dialog, Input, …).
- **Project-specific wrappers** — `<AppButton>` wrapping shadcn's `<Button>` with sensible defaults.
- **Layout primitives** — `<Stack>`, `<Inline>`, `<Card>` if you run a custom layout system.
- **Icon re-exports** — wrap the icon set (lucide / phosphor) so every app pulls from one source.

**Does NOT live there:** business logic (app-level or `packages/services`), routing (apps own routes), state (UI is presentational; client state → apps or `packages/hooks`), API calls (`packages/services`). Packages depend **down, not up** — a package never imports app code.

## Split into orthogonal packages

One mega-package is a red flag; split by concern and let the set grow as patterns repeat:

| Package | Contents |
|---|---|
| `packages/ui` | Visual primitives |
| `packages/styles` | `tokens.css`, `globals.css`, light/dark |
| `packages/tailwind-config` | Shared tailwind preset |
| `packages/typescript-config` | Base `tsconfig.json` |
| `packages/eslint-config` (or biome) | Shared lint rules |
| `packages/hooks` | Reusable hooks (`useDebounce`, `useMediaQuery`) |
| `packages/services` | API clients (typed fetch wrappers) |
| `packages/types` | TS types shared between frontends + types codegen'd from the backend |
| `packages/utils` | Pure helpers — date formatting, string utilities |

Don't force the split — let it grow. A 6-app / 15-package workspace is a realistic upper end.

## Package internals — the same two-level promise

Each package is an app in miniature: a hard skeleton at the top, groups below it.

```
packages/ui/
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts                 # barrel — re-exports the public surface
    ├── button.tsx
    ├── dialog.tsx
    ├── input.tsx
    ├── icons.tsx
    ├── theme-toggle.tsx
    └── …
```

- **UI package**: flat `src/<component>.tsx` while under ~15 components; past that, group by component family (`src/forms/`, `src/overlays/`) — **tripwire T4** below.
- **Services / types packages**: one folder (or file) per domain area, **mirroring the owning backend's domain names** where a mapping exists, so the contract surfaces stay findable by the same vocabulary end to end.
- The same **T5 line caps apply** — shared code gets no exemption (owned by `references/4-feature/caps-and-extraction.md`).

## The export surface

**One export surface per package.** Everything public goes through the package's `index.ts` barrel or its documented sub-path exports (`"./button"`). Consumers never import undocumented internal paths (`@my/ui/src/…`). The export map **is** the package's contract — reviewable on one screen.

```json
// packages/ui/package.json
{
  "name": "@my/ui",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./button": "./src/button.tsx",
    "./*.css": "./src/*.css"
  },
  "dependencies": {
    "react": "catalog:",
    "@radix-ui/react-slot": "^1.1.0"
  }
}
```

The barrel serves `import { Button } from "@my/ui"`; sub-path exports serve tree-shaking deep imports `import { Button } from "@my/ui/button"`.

`packages/styles` exports asset paths, not JS:

```json
// packages/styles/package.json
{
  "name": "@my/styles",
  "private": true,
  "exports": {
    "./tokens.css": "./src/tokens.css",
    "./globals.css": "./src/globals.css",
    "./light-dark.css": "./src/light-dark.css"
  }
}
```

`tokens.css` content/location and light-dark wiring are owned by `references/3-app/frontend/tokens-setup.md`; this file owns only that `packages/styles` re-exports them so one edit propagates to every app on next build.

## Consuming in an app

Depend via `workspace:*` (never a real version like `0.0.1`) and pull shared framework versions from the catalog:

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
// apps/web/src/App.tsx / main.tsx
import { Button } from "@my/ui/button";
import { useAuth } from "@my/hooks";
import { useUsersQuery } from "@my/services";
import "@my/styles/tokens.css";
import "@my/styles/globals.css";
```

Which local `src/` folders a package *replaces* (never both a local `components/ui/` and `packages/ui`) is the workspace-reconciliation rule owned by `references/3-app/frontend/app-skeleton.md`.

## Shared `tailwind-config`

The preset carries brand tokens only; type/spacing scales stay stock (typography policy → `references/3-app/frontend/tokens-setup.md`). Tokens live in CSS (consumable from any tool); Tailwind classes alias to those CSS vars.

```ts
// packages/tailwind-config/index.ts
import type { Config } from "tailwindcss";

const sharedConfig: Omit<Config, "content"> = {
  theme: {
    extend: {
      colors: {
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
// apps/web/tailwind.config.ts — each app supplies its own content globs
import shared from "@my/tailwind-config";

export default {
  ...shared,
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
};
```

## Type packages

`packages/types` holds **cross-app entity types** and types codegen'd from the backend; an app's `api/` may re-export them, never redefine them. The full type/DTO placement doctrine (zod-inferred API types, no cross-domain imports, no `types.ts` dump, both planes) is owned by `references/4-feature/types-and-contracts.md` — this file only fixes that the *package* is where cross-app types sit.

## Tripwire T4 — flat components in a ui package

A ui package with **~15 components flat** in `src/` has outgrown a flat pile — **group by component family** (`src/forms/`, `src/overlays/`, `src/data/`). Crossing the threshold obligates the split or a recorded deferral (one line in the project CLAUDE.md), same as every structural tripwire. The number lives here and in the master table (`references/00_altitude-model.md`).

## Audit checks

- A `packages/ui/src/` with ~15+ flat components and no family grouping and no recorded deferral = T4 finding.
- A consumer importing an undocumented internal path (`@my/ui/src/…`) instead of the export surface = finding.
- A dependency on a package written as a real version (`"0.0.1"`) instead of `workspace:*` = finding (pnpm warns; fix).
- A package importing app-specific code (depending *up*) = red finding.
- One mega `packages/shared` holding UI + logic + types = finding; split by concern.
- A package over the T5 caps = finding (no exemption for shared code).

## Anti-patterns

- One mega `packages/shared` containing everything — split by concern.
- Business logic or state in `packages/utils` / `packages/ui` — keep packages reusable, stateless, presentational.
- Per-app duplication of the same component — extract on third use (tripwire T9, `references/4-feature/caps-and-extraction.md`).
- A package pulling heavy deps consumed by only one app — keep packages slim.
- Hand-written response types living in `packages/types` next to the backend — infer/codegen instead (see `references/4-feature/types-and-contracts.md`).

## See also

- `references/2-repo/grouping-topology.md` — where each package sits (scope/placement) and workspace rooting
- `references/3-app/frontend/workspaces-mechanics.md` — root manifest, `catalog:`, `turbo.json`, `ctl`
- `references/3-app/frontend/app-skeleton.md` — the app `src/` skeleton + workspace reconciliation (never both local and package)
- `references/3-app/frontend/tokens-setup.md` — `tokens.css`, light/dark, typography policy the tailwind preset defers to
- `references/4-feature/types-and-contracts.md` — full type/DTO placement doctrine
- `references/4-feature/caps-and-extraction.md` — file caps (T5), extract-on-third-use (T9)
- `references/00_altitude-model.md` — master tripwire table (T4)
