# Frontend intra-app structure — inside `src/`

The frontend references around this one place the app (`single-frontend.md`, `multi-frontend-workspaces.md`) and its styling system (`design-tokens.md`, `styling-discipline.md`). This reference owns what happens **below `src/`**: the skeleton every frontend keeps, the api-layer rule, where every kind of type lives, and when a feature folder subdivides. It applies to every Vite/React app; Next/Astro variants keep the same doctrine with the framework's routing layer in place of `pages/`.

## The canonical skeleton

The **top level of `src/` is a hard skeleton** — these names, this altitude. What's inside each folder is project-specific.

```
src/
├── layout/      # app shells / structural layouts (sidebar+topbar frame, auth frame, print frame)
├── components/  # common composed components (page header, empty state, confirm dialog) + ui/ primitives (standalone apps)
├── features/    # per-feature substance — subdivided; see the tripwire below
├── pages/       # thin route components mirroring the URL tree; compose from features/
├── hooks/       # shared hooks (feature-specific hooks live in their feature)
├── api/         # THE api access layer — all server communication; see doctrine below
├── lib/         # pure utilities (formatters, parsers — no React, no IO)
├── stores/      # client state (zustand or equivalent); server state belongs to the query layer in api/
└── styles/      # tokens.css + globals — ONLY when no workspace styles package exists
tests/           # cross-cutting test setup (fixtures, msw server); unit tests co-locate with source
public/          # static assets served as-is
```

Empty folders are not created in advance — the skeleton defines where a thing goes **when it appears**, not a set of placeholder directories.

### Layer rules

| Folder | May import from | Never contains |
|---|---|---|
| `pages/` | `features/`, `layout/`, `components/` | business logic, fetch calls, >~50 lines per file |
| `features/` | `api/`, `components/`, `hooks/`, `lib/`, `stores/`, ui package | raw `fetch`/axios, route wiring |
| `layout/` | `components/`, ui package | feature knowledge |
| `components/` | ui package, `lib/` | server communication, feature-specific logic |
| `api/` | `lib/`, `packages/types` | React components |
| `lib/` | nothing app-internal | React, IO |

React context providers co-locate with what they provide (theme provider → `layout/` or the ui package; session provider → `api/` or the services package). A bare `context/` catch-all folder is a kind-folder — don't create one.

### `layout/` subdivides like everything else

Each shell starts as a single file (`layout/app-shell.tsx`). A shell that grows past one file gets its own subfolder that owns all its parts:

```
layout/
├── app-shell/          # grew: frame + its pieces travel together
│   ├── index.tsx
│   ├── sidebar.tsx
│   └── topbar.tsx
├── auth-frame.tsx      # still one file — stays flat
└── settings-frame.tsx
```

This is the general skeleton rule applied recursively: **skeleton names are firm; each entry subdivides when it outgrows a single file** — never a flat pile of `sidebar2.tsx` siblings, never a premature folder for a 40-line frame.

## Workspace reconciliation — packages replace local folders

In a multi-frontend workspace, three of these layers graduate to packages and must **not** be duplicated locally:

| Standalone app | Workspace equivalent |
|---|---|
| `components/ui/` (shadcn primitives + wrappers) | `packages/ui` |
| `styles/` (tokens.css, globals, light-dark) | `packages/styles` |
| auth/session services + API clients shared across apps | `packages/services` |

Both variants are legitimate — the rule is **never both**: creating a local `components/ui/` beside an existing `packages/ui` (or a local `styles/` beside `packages/styles`) is a red audit finding. Shared code lives at the lowest level that contains all its consumers; once a second app consumes it, that level is the workspace package (see `references/architecture/frontend/multi-frontend-workspaces.md` and `shared-ui-package.md`).

## The api-layer doctrine

**No component, hook, page, or store calls `fetch`/axios directly.** All server communication goes through functions in `api/` (or the workspace `packages/services` equivalent), which own:

- **Endpoint paths** — the only place URL strings exist.
- **Request/response typing** — zod schemas parse responses at the boundary; TS types are inferred from them.
- **Error normalization** — every failure becomes one app-wide error shape.
- **The query-key vocabulary** — TanStack Query keys (or equivalent) live beside the functions they cache, so key collisions and invalidation stay reviewable in one place.

`api/` is the single place the backend contract is expressed. When the API changes, the diff is localized to `api/` plus the affected features — nothing else. Internally, `api/` groups by the backend's domain vocabulary (`api/catalog.ts`, `api/access.ts` — or folders when a domain outgrows one file), so the two contract surfaces mirror each other by name.

Enforcement grep (empty output = compliant):

```bash
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src/ | grep -v '^src/api/'
```

## Type placement

Untyped-boundary drift starts exactly where this is left implicit — so it isn't:

| Type kind | Lives in | Rule |
|---|---|---|
| API request/response types | `api/`, beside the functions | inferred from zod schemas (`z.infer<…>`) — never hand-written twins that can drift |
| Cross-app entity types | workspace `packages/types` | an app's `api/` may **re-export**, never redefine |
| Feature-internal types (view models, component state) | inside the feature folder | implementation detail — must not leak into `api/` or packages |
| Store state types | with the store definition | |
| Component prop types | in the component file | |

**No global `types.ts` dumping ground** — a type without an owner is a type nobody updates.

## `pages/` vs `features/`

- `pages/` files are **thin**: route wiring, param parsing, composition of feature components — target **under ~50 lines each**.
- The `pages/` folder tree **mirrors the URL structure** (`pages/settings/members.tsx` ↔ `/settings/members`), so a URL locates its code by inspection.
- All substance lives in `features/`. The router config imports **pages, never feature internals**.

## The feature-folder subdivision tripwire

When a feature folder crosses **~10 source files**, subdivide — by sub-feature (`features/sources/configs/`, `features/sources/runs/`) or by kind within the feature (`pages/`, `dialogs/`, `sections/`) — **whichever axis carries the real seams**. Tests co-locate with what they test through the split. Crossing the threshold obligates the split or a recorded deferral (one line in the project CLAUDE.md), same as every structural tripwire.

## Package internals — the same discipline

Workspace packages (`packages/ui`, `packages/services`, `packages/types`, …) follow the same two-level promise as an app — a hard skeleton at the top, groups below it. They are read by *more* people than app code, so navigability matters more, not less:

- **UI package**: flat `src/<component>.tsx` below **~15 components**; past that, group by component family (`src/forms/`, `src/overlays/`).
- **Services / types packages**: one folder (or file) per domain area, **mirroring the owning backend's domain names** where a mapping exists — the contract surfaces stay findable by the same vocabulary end to end.
- **One export surface**: everything public goes through the package's `index.ts` or its documented sub-path exports (`"./button"`). Consumers never import undocumented internal paths (`@my/ui/src/…`). The export map IS the package's contract — reviewable in one screen.
- The same thresholds apply — files-per-folder, 500/300 line caps. Shared code gets no exemption.

## Audit checks

- The `fetch`/axios grep above → any hit outside `api/` (or `packages/services`) = finding.
- Count files per feature folder → **~10+ flat with no recorded deferral = finding**.
- A local `components/ui/` or `styles/` coexisting with the workspace package = red finding.
- `pages/` files doing substance (well past ~50 lines, or containing fetch/query logic) = finding.
- A global `types.ts` accumulating unrelated types = finding.
- Missing skeleton layers in a grown app (routes importing feature internals because `pages/` doesn't exist; fetch logic inside features because `api/` doesn't exist) = finding.

## Anti-patterns

- A 30-file flat feature folder — the frontend twin of a backend with a dozen flat feature folders; same reflex, subdivide.
- Fetch logic inside components "just this once" — the api layer dies by exceptions.
- Hand-written response types next to zod schemas — twins drift; infer instead.
- `pages/` as a second components folder — pages route and compose, nothing else.
- A `context/`, `helpers/`, or `types.ts` catch-all — ownerless code accumulates silently.
- Duplicating a workspace package locally "to move fast" — two sources of truth, immediate drift.

## See also

- `references/architecture/frontend/single-frontend.md` — where the app itself sits; this reference owns what's below its `src/`
- `references/architecture/frontend/multi-frontend-workspaces.md`, `shared-ui-package.md` — the workspace/package layer
- `references/architecture/frontend/styling-discipline.md` — the styling rules feature code lives under
- `references/architecture/modularity/domain-grouping-tripwire.md` — the backend twin + the domain vocabulary `api/` mirrors
- `references/levels/04_feature.md` — the feature-level charter this reference serves
