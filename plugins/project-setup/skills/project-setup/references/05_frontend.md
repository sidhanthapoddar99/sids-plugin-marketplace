# Frontend — how a frontend is built

The kind is chosen in `04_stack.md`; the routing in `03_routing.md`. This page is the inside: the theme, the typography policy, the folder shape, and the rules module code lives under. Template: `template/apps/example-single-web-app-vite/src/` (one frontend, Vite), `template/apps/example-dashboard-nextjs/src/` (Next.js), `template/apps/packages/ui/` (shared theme).

## Theme

The theme and the components are one thing, with one internal shape wherever it lives. The shape is `template/apps/packages/ui/src/`: `styles/tokens.css` holds raw values only, colours by role, light on `:root` and dark on `[data-theme="dark"]`; `styles/globals.css` is the one Tailwind entry that maps tokens onto utilities and the shadcn aliases; `styles/elements.css` holds the element resets; `components/` holds the shadcn components, one file each; `lib/utils.ts` holds `cn()`. Each file's header comment says what it holds. `lib/theme.ts`, the one theme switcher, is written per project to the rules under Switching below; the template does not carry it.

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
- The package set grows by concern: `ui`, `types`, `tsconfig` first; `services` (the typed API client and query keys two frontends share, the package form of `lib/api/`) and `hooks` when a second frontend needs them. A second frontend never re-implements `lib/api/`.
- Never both: a local `components/ui/` or `styles/` beside the shared package is a red finding. The move is one direction. The template shows both shapes on purpose (`example-single-web-app-vite/src/styles/` and `packages/ui/`); a real repo keeps one and deletes the other at bootstrap.

### Switching

`tokens.css` defines both modes; something must set `[data-theme]`. One implementation, `lib/theme.ts`, used by every frontend, because two switchers disagree on the stored key and the page flashes. Write it to these rules:

| Step | Rule |
|---|---|
| Resolve | stored choice (`localStorage`) → `prefers-color-scheme` → `light`. |
| Apply | `document.documentElement.dataset.theme = value`. Persist on change. Follow the OS only while no choice is stored. |
| First paint | A blocking inline `<script>` in `index.html` (Vite) or the root layout (Next.js) sets the attribute before the first render. `useEffect` alone flashes the wrong theme for one frame on every load, and on SSR pages the server has no `localStorage`; the inline script is the fix, not a hydration trick. Next.js: `suppressHydrationWarning` on `<html>`, because the script mutates the attribute before hydration. |
| Toggle | One component in the ui package. Module code never touches the attribute. |

## Typography — stock vocabulary, strict policy

Two layers. The **vocabulary** is Tailwind's stock theme, untouched: the full type scale, full weight set, stock spacing, never remapped (`text-sm` is 14px, always), no custom size utilities (`type-md`). The **policy** is a small allowlist written in `AGENTS.md` that says what module code may use:

| Default allowlist | Use |
|---|---|
| `text-sm` | ~90 % of the UI: tables, controls, labels, descriptions |
| `text-base` | headings. The only heading size. |
| `text-xs` | sparingly: badges, timestamps, fine meta |
| `font-normal` | everywhere |
| one of `font-medium` / `font-semibold` | the single emphasis weight, chosen per project, used only inside ui-package primitives |

Hierarchy comes from size and foreground colour, never from weight. Every other size and weight exists and is banned in module code: banned, not deleted. A hero surface gets them through a primitive created in a design pass. Why policy and not vocabulary: a policy change is one line in `AGENTS.md` plus a grep; a vocabulary change is a migration.

Anti-patterns: remapping stock names; size×weight rungs (`xl=28/700, lg=20/600` is three weights in disguise); a second weight "for this one heading".

## Precedence over `frontend-design`

With `tokens.css` and a ui package in place, this page overrides every general design instruction, including the `frontend-design` skill's "be bold, avoid system fonts, never converge". Convergence is the design. `frontend-design` is right on day one, to establish the brand, the tokens and the primitives, and wrong every day after. The one exception is an explicit design-exploration pass: screenshots, iterations, bold directions; the winner graduates into tokens and primitive variants before the pass ends, and exploratory inline styles never ship in module code. This rule is written into `AGENTS.md` because skills are not always loaded and the brief is.

After any UI change: screenshot light and dark and check against the brand guidelines (`design/brand-guidelines/` when it exists; `tokens.css` is its executable form) before calling it done.

## The folder shape

Every frontend draws from the same five folders under `src/`, plus one routing folder whose name the framework sets. A route file picks a layout and mounts one module. That sentence is the whole design; the folders exist so each word in it has one home. A folder exists when used: a static landing site has no `lib/`, and a docs site holds its content in its pages, so it has no `modules/` either.

`@/` is the import alias for `src/`. Each app's `tsconfig.json` maps `@/*` to `./src/*`. A Vite app repeats the map as `resolve.alias` in `vite.config.ts`, because Vite does not read tsconfig paths; Next.js does.

| Folder | Holds | Answers |
|---|---|---|
| the routing folder | one file per URL. Thin: pick a layout, mount one module, validate params | which URL shows what |
| `layout/<name>/` | the frames: sidebar, header, footer, `<Outlet/>` or `{children}`. No data, no business logic | what surrounds the content |
| `modules/<name>/` | one folder per screen-level assembly: `index.tsx` is the assembled screen, and the folder owns its `components/`, `functions/`, `modules/` and `types.ts` | what a screen shows |
| `components/` | shared UI with no business logic. `components/ui/` is the shadcn primitives when the app owns its theme | what every screen composes |
| `lib/` | shared non-UI code: `api/`, `stores/`, `hooks/`, `utils.ts` | what every screen calls |
| `styles/` | `tokens.css`, `globals.css`, `elements.css`, when the app owns its theme | the theme |

The routing folder per framework, because each framework owns file routing and its name is the one its docs use:

| Framework | Routing folder | Tool | Template |
|---|---|---|---|
| Vite | `routes/` and a generated `routeTree.gen.ts` | TanStack Router, file-based. The plugin goes first in `vite.config.ts`. A route exists only when its file does, and a wrong link is a type error | `example-single-web-app-vite/src/`, `example-multi-web-app/app/src/` |
| Next.js | `app/` | Built in. Route groups `(name)/` wrap a subtree in a layout without a URL segment | `example-dashboard-nextjs/src/`, `example-multi-web-app/landing/src/` |
| Astro | `pages/` | Built in. A page holds its content, because on a docs site the content is the screen; the one CSS import lives in `layout/` | `example-multi-web-app/docs/src/` |

Vite, the single-frontend shape. Comments in the template files say what each holds and what it may import.

```
src/
├── main.tsx                      # mounts the router. Nothing else lives here
├── routeTree.gen.ts              # generated by TanStack Router. Never edited
├── routes/                       # file path = URL. A route picks a layout and mounts one module
│   ├── __root.tsx                # the outermost shell: providers, error boundary
│   ├── index.tsx                 # /              → modules/home
│   ├── _app.tsx                  # pathless layout route: wraps its children in layout/app
│   ├── _app/dashboard.tsx        # /dashboard     → modules/dashboard
│   └── _app/settings.$tab.tsx    # /settings/:tab → modules/settings
├── layout/
│   ├── app/                      # sidebar + header + <Outlet/>
│   │   ├── index.tsx
│   │   └── sidebar.tsx
│   └── marketing/index.tsx
├── modules/
│   └── dashboard/
│       ├── index.tsx             # the assembled screen. The only export a route imports
│       ├── components/           # pieces only this module uses
│       ├── functions/            # logic only this module uses: hooks, queries, formatters
│       ├── modules/overview/     # sub-assemblies, one level deep: a tab, a panel
│       └── types.ts              # types only this module uses
├── components/
│   ├── index.ts                  # shared composed UI: page header, empty state
│   └── ui/                       # shadcn primitives
├── lib/
│   ├── api/                      # client, one file per backend domain, zod at the boundary
│   ├── stores/                   # client state
│   ├── hooks/                    # shared hooks
│   └── utils.ts                  # cn()
└── styles/
```

Next.js, the same tree with `app/` in place of `routes/` and `main.tsx`:

```
src/
├── app/
│   ├── layout.tsx                # the root shell. Same job as __root.tsx
│   ├── page.tsx                  # /              → modules/home
│   └── (app)/                    # route group: wraps its children in layout/app. Same job as _app.tsx
│       ├── layout.tsx            # renders <AppLayout>{children}</AppLayout> and nothing else
│       ├── dashboard/page.tsx    # /dashboard     → modules/dashboard
│       └── settings/[tab]/page.tsx  # /settings/:tab → modules/settings
├── layout/                       # unchanged
├── modules/                      # unchanged. A module with state marks itself "use client"; the page stays a server component
├── components/                   # unchanged
├── lib/                          # unchanged
└── styles/                       # unchanged, or the ui package
```

The rules the tree implies. Each is a one-line comment in the template file it governs, and the table is their one home:

| Layer | May import | Never | Why |
|---|---|---|---|
| routing folder | one layout, one module's `index.tsx`, `zod` for params | `lib/api`, `fetch`, a module's other files. One exception: a Next.js server page may fetch by service name, because it runs on the server where the browser client cannot | a route decides where, not what |
| `layout/` | `components/`, `lib/stores` for session and theme | a module, `lib/api` | the same frame serves every screen |
| `modules/<x>/` | its own folders, `components/`, `lib/` | a route, a layout, another module | a module can sit under two routes and never depends on a sibling |
| `modules/<x>/modules/` | one level deep | a second level, a sibling module's sub-module | a sub-module two modules need becomes a component under `components/`, because modules never import each other |
| `components/` | `components/ui`, `lib/utils` | `lib/api`, a store, a module | it renders props |
| `lib/api` | `lib/utils`, `@scope/types` | a component, a store, React | it is the one server boundary |
| `lib/stores` | `lib/utils` | `lib/api`, a module, a component | client state is never server state; TanStack Query in `lib/api` owns that |
| `lib/hooks` | `lib/api`, `lib/stores`, `lib/utils` | a module, a component | a shared hook binds state to data and nothing above it |
| `lib/utils` | nothing app-internal | React, `fetch` | it must lift out with the app |

Promotion is the same rule as packages: a piece moves up one scope at its second consumer. UI to `components/`, logic to `lib/`, a type to `lib/` beside its api domain file, and to `packages/ui`, `packages/services` or `@scope/types` at the second frontend. `functions/` inside a module holds hooks, queries and formatters; it is one folder rather than `hooks/` and `utils/`, because a module's logic is small enough to sit together.

No `context/`, `helpers/`, `utils/`, `types.ts` at the top of `src/`. A type has an owner at the lowest level that contains its consumers: one module, its `types.ts`; two modules, `lib/`; two apps, `@scope/types`.

## The api layer

No component, hook, route or store calls `fetch` directly. `lib/api/` owns four things: the endpoint paths (the only place a URL string exists), the response boundary (zod at the edge, types inferred with `z.infer`, nothing unvalidated enters the app), error normalisation (one app-wide error shape), and the query keys (beside the functions they cache, so invalidation is reviewable in one place). `lib/api/` groups by the backend's domain names, never by UI screen, so the two contract surfaces mirror each other. When the API changes, the diff is `lib/api/` plus the affected modules and nothing else. The one exception is the Next.js server page, and the import table above is its home.

## Module rules

| Rule | Detail |
|---|---|
| Compose, do not style | Module code composes primitives and their documented variants. Raw utilities only for layout glue (flex, grid, gap, padding on wrappers). |
| A look that does not exist | Add it to the primitive as a CVA variant or prop (`<Card variant="media">`), then use it. Never improvise inline. |
| Fold on the second use | The same utility combination twice → a primitive variant before continuing. Stricter than the rule of three for logic (`11_conventions.md`), because a utility string is cheap to extract and styling duplication is where drift starts. |
| Subdivide at ~10 files | Inside `components/` or `functions/` of a module, by sub-module or by kind, whichever axis the files change along together. A tab or panel that earns its own files becomes `modules/<sub>/`. The number lives in `11_conventions.md` § Caps. |
| Caps | Component 150 lines, route file 50: split. The numbers live in `11_conventions.md` § Caps. A piece imported by two modules: promote it. |
| Cross the boundary with types | A module exposes `index.tsx`. Nobody reaches into another module's files. Never import a DTO across modules to reuse a shape; duplicate it. `11_conventions.md` § Scope says why. |

Mechanical checks (empty output = compliant; a lint rule per `10b_static-checks.md` § Layer rules is the durable form):

```bash
grep -rEn --include='*.tsx' 'text-\[|bg-\[#|\bp-\[|var\(--' src/modules src/routes src/app src/layout      # arbitrary values, raw var()
grep -rEn --include='*.tsx' '\btext-(lg|xl|[2-9]xl)\b|\bfont-(light|medium|semibold|bold)\b' src/modules src/routes src/app src/layout   # outside the allowlist
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src | grep -v '^src/lib/api/' | grep -v '^src/app/.*page\.tsx'  # fetch outside lib/api (server pages excepted)
grep -rEn --include='*.tsx' "from ['\"](\.\./)+modules/|from ['\"]@/modules/" src/modules   # a module importing a sibling module
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
