# Frontend — how a frontend is built

The kind is chosen in `04_stack.md`; the routing in `03_routing.md`. This page is the inside: the theme, the typography policy, the folder shape, and the rules feature code lives under. Template: `template/apps/example-single-web-app-vite/src/` (one frontend), `template/apps/packages/ui/` (shared).

## Theme

The theme and the components are one thing, with one internal shape wherever it lives:

```
styles/     tokens.css    raw values only. Colours by role (--bg-1..3, --fg-1..3, --border-1..2, --success,
                          --warning, --danger, --info), light on :root, dark on [data-theme="dark"]. Radius base,
                          fonts, motion, a z-index scale. Nothing else switches by theme.
            globals.css   the Tailwind entry. @import tailwindcss + tokens + elements. @theme = the stock scales.
                          @theme inline = tokens mapped onto utilities (--color-bg-1: var(--bg-1)) plus the shadcn
                          aliases (--color-background, --color-primary …). @source points at the components.
            elements.css  base element resets that consume tokens.
components/ shadcn components, one file each, a folder for compound ones. Every visual decision lives here.
lib/utils.ts  cn()
lib/theme.ts  the one theme switcher (below)
```

| Product has | Where the shape lives | Import in the app |
|---|---|---|
| one frontend | inside the app: `src/styles/`, `src/components/ui/`, `src/lib/` — the standard shadcn layout | `import "./styles/globals.css"` |
| two or more | `apps/packages/ui/src/`, the same folders, linked by every frontend | `import "@scope/ui/globals.css"` |

Moving from the first to the second is a move, not a rewrite. Rules that hold in both:

- One CSS import per app, in the entry file. Nothing else imports CSS.
- A colour is named once, in `tokens.css`, by role, never by hue. A component uses the utility (`bg-bg-1`, `border-thin`), never `var(--…)`, never a hex. `var(--…)` is legal only inside `.css` files and the ui package's own internals.
- A token for a one-off value is a magic number with a name. A value used once is not a token.
- Variants differ by fill and border; sizes use the stock scale (`px-3 py-1 text-sm rounded-sm`).
- `cn()` is taught the named utilities `globals.css` adds (`border-thin`, `duration-fast`), or tailwind-merge drops them.
- In the package, React and Tailwind are peerDependencies; React optional, so a CSS-only consumer (Astro docs) links it without React.
- ~15 flat components → group by family (`form/`, `overlay/`, `data/`). Never one mega `packages/shared`; split by concern; a package never imports app code.
- The package set grows by concern: `ui`, `types`, `tsconfig` first; `services` (the typed API client and query keys two frontends share, the package form of `api/`) and `hooks` when a second frontend needs them. A second frontend never re-implements `api/`.
- Never both: a local `components/ui/` or `styles/` beside the shared package is a red finding. The move is one direction. The template shows both shapes on purpose (`example-single-web-app-vite/src/styles/` and `packages/ui/`); a real repo keeps one and deletes the other at bootstrap.

### Switching

`tokens.css` defines both modes; something must set `[data-theme]`. One implementation, `lib/theme.ts`, used by every frontend:

| Step | Rule |
|---|---|
| Resolve | stored choice (`localStorage`) → `prefers-color-scheme` → `light`. |
| Apply | `document.documentElement.dataset.theme = value`. Persist on change. Follow the OS only while no choice is stored. |
| First paint | A blocking inline `<script>` in `index.html` (Vite) or the root layout (Next.js) sets the attribute before the first render. `useEffect` alone flashes the wrong theme for one frame on every load, and on SSR pages the server has no `localStorage`; the inline script is the fix, not a hydration trick. Next.js: `suppressHydrationWarning` on `<html>`, because the script mutates the attribute before hydration. |
| Toggle | One component in the ui package. Feature code never touches the attribute. |

## Typography — stock vocabulary, strict policy

Two layers. The **vocabulary** is Tailwind's stock theme, untouched: the full type scale, full weight set, stock spacing, never remapped (`text-sm` is 14px, always), no custom size utilities (`type-md`). The **policy** is a small allowlist written in `AGENTS.md` that says what feature code may use:

| Default allowlist | Use |
|---|---|
| `text-sm` | ~90 % of the UI: tables, controls, labels, descriptions |
| `text-base` | headings. The only heading size. |
| `text-xs` | sparingly: badges, timestamps, fine meta |
| `font-normal` | everywhere |
| one of `font-medium` / `font-semibold` | the single emphasis weight, chosen per project, used only inside ui-package primitives |

Hierarchy comes from size and foreground colour, never from weight. Every other size and weight exists and is banned in feature code: banned, not deleted. A hero surface gets them through a primitive created in a design pass. Why policy and not vocabulary: a policy change is one line in `AGENTS.md` plus a grep; a vocabulary change is a migration.

Anti-patterns: remapping stock names; size×weight rungs (`xl=28/700, lg=20/600` is three weights in disguise); a second weight "for this one heading".

## Precedence over `frontend-design`

With `tokens.css` and a ui package in place, this page overrides every general design instruction, including the `frontend-design` skill's "be bold, avoid system fonts, never converge". Convergence is the design. `frontend-design` is right on day one, to establish the brand, the tokens and the primitives, and wrong every day after. The one exception is an explicit design-exploration pass: screenshots, iterations, bold directions; the winner graduates into tokens and primitive variants before the pass ends, and exploratory inline styles never ship in feature code. This rule is written into `AGENTS.md` because skills are not always loaded and the brief is.

After any UI change: screenshot light and dark and check against the brand guidelines (`design/brand-guidelines/` when it exists; `tokens.css` is its executable form) before calling it done.

## The folder shape

```
src/
├── main.tsx             the one CSS import, the router, the theme script's counterpart
├── styles/              (single frontend) or the ui package
├── components/ui/       (single frontend) or the ui package — primitives, never features
├── layout/              shells: the app frame, sidebars, page chrome. A folder when a shell outgrows one file
├── pages/               thin route components, mirroring the URL tree. ~50 lines. The router imports pages only
├── features/<name>/     the substance: components, hooks, state, local types. index.ts is the only door
├── api/                 the one server boundary. Grouped by the backend's domain vocabulary (api/users.ts)
├── stores/              client state (zustand). Only what more than one feature reads
├── hooks/               a hook two features share. Feature-local hooks stay in the feature
└── lib/                 pure helpers. Imports nothing app-internal, no React, no IO
```

| Layer | May import | Never |
|---|---|---|
| `lib/` | nothing app-internal | React, `fetch`, a feature |
| `api/` | `lib/`, `@scope/types` | a component, a store |
| `components/ui/` | `lib/` | `api/`, a feature, a store |
| `features/` | `api/`, `stores/`, `components/ui/`, `lib/`, another feature's `index.ts` | another feature's internals, `fetch` |
| `pages/` | features, layout | `api/` directly, `fetch` |
| `stores/` | `lib/` | `api/`, a component |
| `hooks/` | `api/`, `stores/`, `lib/` | a feature, a component |

No `context/`, `helpers/`, `utils/`, `types.ts` at the top of `src/`. A type has an owner at the lowest level that contains its consumers; a cross-app entity is in `@scope/types`.

## The api layer

No component, hook, page or store calls `fetch` directly. `api/` owns four things: the endpoint paths (the only place a URL string exists), the response boundary (zod at the edge, types inferred with `z.infer`, nothing unvalidated enters the app), error normalisation (one app-wide error shape), and the query keys (beside the functions they cache, so invalidation is reviewable in one place). `api/` groups by the backend's domain names, never by UI screen, so the two contract surfaces mirror each other. When the API changes, the diff is `api/` plus the affected features and nothing else.

## Feature rules

| Rule | Detail |
|---|---|
| Compose, do not style | Feature code composes primitives and their documented variants. Raw utilities only for layout glue (flex, grid, gap, padding on wrappers). |
| A look that does not exist | Add it to the primitive as a CVA variant or prop (`<Card variant="media">`), then use it. Never improvise inline. |
| Fold on the second use | The same utility combination twice → a primitive variant before continuing. Stricter than the rule of three for logic (`11_conventions.md`), because a utility string is cheap to extract and styling duplication is where drift starts. |
| Subdivide at ~10 files | Inside the feature folder, by sub-feature or by kind, whichever carries the real seams. Never fragment across siblings. |
| Caps | A component over 150 lines, a page over 50: split. A feature imported by two features: extract to the app scope or a package. |
| Cross the boundary with types | A feature exposes `index.ts`. Nobody reaches into another feature's files. Never import a DTO across features to reuse a shape; duplicate it. |

Mechanical checks (empty output = compliant; a conformance test in `10_testing.md` is the durable form):

```bash
grep -rEn --include='*.tsx' 'text-\[|bg-\[#|\bp-\[|var\(--' src/features src/pages      # arbitrary values, raw var()
grep -rEn --include='*.tsx' '\btext-(lg|xl|[2-9]xl)\b|\bfont-(light|medium|semibold|bold)\b' src/features src/pages   # outside the allowlist
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src | grep -v '^src/api/'  # fetch outside api/
```

grep owns the recursion (`-r --include`), never a shell glob (`**` degrades to one level under bash). In a hook, invert the exit code.

## PWA

A PWA is the SPA plus a manifest and a service worker, generated by the build, never a hand-written `sw.js`. Installability: HTTPS, maskable 192 and 512 icons, `start_url`, `display: standalone`; Lighthouse's audit is the test. Choose the offline scope explicitly: none, read-only shell, or full sync; half-offline is worse than online. Never blanket-cache `/api/*`; freshness per route. A new build must tell the user: a "refresh" prompt on `waiting`, never a silent stale app. Choose native instead when the product needs store presence, background execution, device APIs, or reliable iOS push (web push works only for an installed PWA).

## Published package or SDK

When the product is a library, it lives in `apps/packages/<name>/` and the frontend beside it is a dev harness (`01_layout.md`). Rules that differ from an app:

| Rule | Detail |
|---|---|
| Public surface | An `exports` map names every entry; consumers cannot deep-import. `files: ["dist"]`. The same holds for an internal package: one export surface, no `src/…` imports from a consumer. |
| Build | A library build (`vite build --lib`, tsup), `external: ["react"]`, framework in `devDependencies` + `peerDependencies`. Not app bundling. |
| Internal split | A react-less `core` package for authors, bundled into the one published artifact (`noExternal`) for consumers. |
| Source-only phase | `private: true`, `exports` pointing at `src/`, no `dist/`. Ends at the first external consumer. Record it in `AGENTS.md` as the chosen stage. |
| Not a product | The harness says so in three places: `private: true`, the README's first line, and a comment in its build config. |
| Embeddable | Reads no env: services, storage and theme arrive as one typed `config` object at mount, the seam contract. No module-level singletons; the same package may mount several times on one page. Clean teardown on unmount. |
