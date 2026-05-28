# Layout 06 — embeddable package + reference host

The repo's **deliverable is a published package** — a UI component / SDK / headless engine — that a *separate, external host* installs and runs. The repo also ships a thin **reference host** (`apps/web`) so you can develop and demo the package, but that app is **not the product**. Think "Google-Workspace-style embed": the editor is the product; it mounts inside many different host apps, each supplying its own services and storage.

This is the layout the deployed-vs-distributed question (Batch 1, Q3a) routes to. It's orthogonal to backend/frontend count — a Layout 06 repo can internally have a BFF, a reference frontend, and shared packages, but its *reason to exist* is the published artifact.

## When it fits

- The deliverable is a **package consumers install** (`npm i @you/editor`, `pip install you-engine`), not a service you deploy.
- A **different, external repo** is the real host. Your repo's app is a harness.
- "Embeddable", "SDK", "library-as-product", "the frontend *is* the product", "mounts in someone else's app".
- The product must run inside a host it doesn't control — so it can't bake in URLs, secrets, or "where saves go".

If instead the repo *runs* the product (you `ctl prod` it and that's the live thing), it's 01–08, not 09.

## The two-host distinction (the crux)

- **Reference host** (`apps/web` in this repo): a dev harness. Wires the package up with throwaway/local services so you can see it work, write stories, run e2e. Ships to nobody as "the product".
- **Real host** (external repo, not in this repo): the consumer's app. It installs the package, owns the React instance, and fills the embedding seams (services, storage, theme) with *its* implementations.

Treating the reference host as "the app" is the exact mistake that makes "independent package" read as "headless service". It isn't headless — it's **embeddable**.

## Tree

```
my-editor/                              # the product is the package below
├── package.json                        # workspace root, private
├── pnpm-workspace.yaml                 # (or bun workspaces)
├── turbo.json
├── ctl                                 # ctl dev (reference host) / build / publish
├── packages/
│   └── editor/                         # ← THE PRODUCT (published)
│       ├── package.json                # name "@you/editor"; exports; peerDeps; files
│       ├── tsup.config.ts              # or rollup — library build, not app bundling
│       ├── src/
│       │   ├── index.ts                # public entry — the package's API surface
│       │   ├── Editor.tsx              # the embeddable component
│       │   ├── config.ts               # the props/config API: services, storage, theme seams
│       │   ├── core/                   # headless engine (react-less; see split below)
│       │   └── ui/                     # React UI layer
│       ├── tests/
│       └── README.md                   # how an EXTERNAL host installs + mounts it
├── packages/
│   └── core/                           # optional — headless engine as its own package
│       ├── package.json                # NO react dep → enforces UI-free at the boundary
│       └── src/
├── apps/
│   ├── web/                            # ← REFERENCE HOST (dev harness, not the product)
│   │   ├── package.json                # depends on @you/editor via workspace
│   │   ├── .env / .env.example         # local/throwaway service URLs for the demo
│   │   ├── vite.config.ts
│   │   └── src/                        # mounts <Editor config={...localImpls} />
│   └── api/                            # OPTIONAL BFF — only if the reference host needs one
│       ├── app/
│       └── README.md
├── docker/                             # optional — only for the reference host's deps
├── .changeset/                         # if using changesets for versioning
├── docs/  .claude/  CLAUDE.md  README.md  LICENSE
```

The published thing is `packages/editor/`. Everything in `apps/` exists to develop it.

## Embedding seams — inversion of control

The package **never** reaches out for its own dependencies. The host injects them through a config/props API. The package declares *what it needs*; the host decides *how*.

```ts
// packages/editor/src/config.ts — the seam contract
export interface EditorConfig {
  // services — URLs/clients the host owns (never baked into the package)
  services: { apiBaseUrl: string; authToken: () => Promise<string> };
  // storage — the host decides WHERE saves go; package only calls these hooks
  storage: {
    onSave: (doc: Doc) => Promise<void>;
    open: (id: string) => Promise<Doc>;
    cache?: KVLike;
  };
  // runtime / theme — host controls look + behaviour
  theme?: "light" | "dark" | TokenOverrides;
  features?: Partial<FeatureFlags>;
}
```

```tsx
// external host (a DIFFERENT repo) mounts it:
<Editor config={{
  services: { apiBaseUrl: "/api", authToken: host.getToken },
  storage: { onSave: host.saveDoc, open: host.loadDoc },
  theme: host.theme,
}} />
```

Rules that fall out of this:

- **Secrets and "where saves go" are never baked in.** They arrive via `config` at mount time. The package has no `.env` of its own that ships to consumers.
- **Per-instance mount model** (Google-Workspace-style): the same package mounts many times, each instance configured independently — different `apiBaseUrl`, different storage, different theme. No module-level global state that assumes one host.
- The **reference host** fills these seams with local/throwaway impls; the **real host** fills them with production ones. Same contract, two implementations — the package can't tell the difference.

## Publishing mechanics (the part deployed layouts ignore)

A published package is built and versioned differently from a deployed app:

- **`package.json` `exports`** — declare the public entry points explicitly; don't let consumers deep-import internals.
  ```jsonc
  {
    "name": "@you/editor",
    "exports": { ".": { "types": "./dist/index.d.ts", "import": "./dist/index.mjs" } },
    "files": ["dist"],
    "peerDependencies": { "react": ">=18", "react-dom": ">=18" }
  }
  ```
- **React as a `peerDependency`, not a dependency.** The *host* owns the single React instance — bundling your own React causes the "invalid hook call / two Reacts" class of bugs. Same for any framework runtime the host provides.
- **Library build tooling** (`tsup`, `rollup`, `vite build --lib`) — emits ESM + types for consumption, not an app bundle. This is *not* the same as building the reference host (which uses normal Vite app bundling).
- **Versioning + publishing** — semver, a changelog (changesets work well in a workspace), `npm publish` (or PyPI for a Python engine). `ctl publish` wraps it. The reference host is never published.

## Single-artifact delivery (named convention)

You want two opposing things: a clean internal boundary (the headless `core` must stay UI-free) **and** a single thing consumers install (not "install these four packages").

**Convention: keep internal workspace packages for the boundary, bundle them into one published artifact.**

- Keep `packages/core/` with a **react-less `package.json`** — its dependency graph *mechanically enforces* that the engine has no UI. If someone imports React into `core`, the build breaks. That's the boundary doing its job.
- At publish time, **bundle `core` into the published package** rather than listing it as an external dependency — e.g. tsup's `noExternal: ["@you/core"]`. Consumers `npm i @you/editor` and get one artifact; the internal split is invisible to them.

So: **multiple workspace packages for the authors, one published package for the consumers.** Boundary preserved, install story simple.

## `ctl` shape

```
ctl dev            # run the REFERENCE HOST (apps/web) with the package hot-linked
ctl build          # library build of the package(s) — tsup/rollup, ESM + types
ctl test           # package unit tests + reference-host e2e
ctl publish        # version bump + npm/PyPI publish (NOT the reference host)
ctl clean
ctl help
```

`ctl dev` is the reference host, deliberately — day-to-day you develop the package *through* its harness. There is no `ctl prod` for "the product" because the product isn't deployed from here; it ships via `ctl publish`.

## What's different from the deployed layouts

- The thing in `packages/` is **the product**, not internal shared code (the third `apps/`-vs-`packages/` category — see `references/00_decision-tree.md`).
- `apps/web` is a **reference host**, not the deliverable.
- React is a **peerDependency**; the package never owns the React instance.
- Versioning + publishing exist; deployment (of the package) does not.
- Config arrives by **injection at mount**, not from a root `.env` the package reads.

## Cross-references

- `references/architecture/frontend/embeddable-package-and-reference-host.md` — the embedding-seams + publishing detail (exports, peerDeps, single-artifact bundling, per-instance mount).
- `references/00_decision-tree.md` § "`apps/` vs `packages/` — three categories" — where this fits in the placement model.
- `references/architecture/frontend/multi-frontend-workspaces.md` — the workspace mechanics (pnpm/turbo) this reuses for the package + reference-host split.

## Common mistakes to avoid

- Treating `apps/web` as "the app" — it's a harness; the package is the product.
- Bundling React into the package instead of `peerDependencies` — two-Reacts bugs.
- Baking service URLs / secrets / save-locations into the package — they belong in the host-injected `config`.
- Module-level singletons that assume one host — breaks the per-instance mount model.
- Publishing four packages when one bundled artifact (`noExternal`) is what consumers want.
- Skipping the headless/UI split — without a react-less `core` package, UI leaks into the engine and the boundary rots.

## Real-world reference

No repo in Sid's current portfolio is a canonical Layout 06 yet. When one lands (an embeddable editor / SDK whose consumer is an external host), add it here as the canonical example. Until then, propose the pattern on its own merits and flag the absence.
