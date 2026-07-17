# Layout 06 — embeddable package + reference host

Owns the **repo shape**, **publishing mechanics**, and **single-artifact delivery** for a repo whose deliverable is a *published package* — a UI component / SDK / headless engine — that a **separate, external host** installs and runs. The repo also ships a thin reference host (`apps/web`) to develop and demo the package, but that app is **not the product**. Think "Google-Workspace-style embed": the editor is the product; it mounts inside many host apps, each supplying its own services and storage.

Scope boundaries (owned elsewhere — link, don't restate):

- **When** a repo is distributed-not-deployed (the deployed-vs-distributed decision that routes here): owned by `references/1-ecosystem/repo-boundaries.md`.
- **Embedding seams** — the IoC config/props API, injection rules, per-instance mount model: owned by `references/3-app/05-package/02_embeddable-seams.md`.

This layout is orthogonal to backend/frontend count: a Layout 06 repo can internally have a BFF, a reference frontend, and shared packages, but its *reason to exist* is the published artifact. If the repo instead *runs* the product (`ctl up prod` and that's the live thing), it's Layout 01–05, not 06.

## The two-host distinction (needed to read the tree)

- **Reference host** (`apps/web`, in this repo): a dev harness. Wires the package up with throwaway/local services so you can see it work, write stories, run e2e. Ships to nobody as "the product".
- **Real host** (an external repo, *not* here): the consumer's app. It installs the package, owns the React instance, and fills the embedding seams with *its* implementations.

Treating the reference host as "the app" is the mistake that makes an independent package read as a headless service. It isn't headless — it's **embeddable**. How the two hosts fill the seams is owned by `references/3-app/05-package/02_embeddable-seams.md`.

## Tree

```
my-editor/                              # the product is the package below
├── package.json                        # workspace root, private
├── pnpm-workspace.yaml                 # (or bun workspaces)
├── turbo.json
├── ctl                                 # ctl dev (reference host) / build / publish
├── packages/
│   ├── editor/                         # ← THE PRODUCT (published)
│   │   ├── package.json                # name "@you/editor"; exports; peerDeps; files
│   │   ├── tsup.config.ts              # library build (not app bundling)
│   │   ├── src/
│   │   │   ├── index.ts                # public entry — the package's API surface
│   │   │   ├── Editor.tsx              # the embeddable component
│   │   │   ├── config.ts               # the seam contract → references/3-app/05-package/02_embeddable-seams.md
│   │   │   ├── core/                   # headless engine (react-less; see split below)
│   │   │   └── ui/                     # React UI layer
│   │   ├── tests/
│   │   └── README.md                   # how an EXTERNAL host installs + mounts it
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
- **Framework runtime as a `peerDependency`, not a dependency.** The *host* owns the single React instance — bundling your own React causes the "invalid hook call / two Reacts" class of bugs. Same for any runtime the host provides.
- **Library build tooling** (`tsup`, `rollup`, `vite build --lib`) — emits ESM + types for consumption, not an app bundle. This is *not* the same as building the reference host (normal Vite app bundling). Config shape: `external: ["react", "react-dom"]` (peers stay the host's) and `noExternal` for internal engine packages bundled into the artifact; the framework sits in `devDependencies` for build/dev only — never a runtime `dependency`.
- **Versioning + publishing** — semver, a changelog (changesets work well in a workspace), `npm publish` (or PyPI for a Python engine). `ctl publish` wraps it. The reference host is never published.

## Single-artifact delivery (named convention)

Two opposing wants: a clean internal boundary (the headless `core` stays UI-free) **and** one thing consumers install (not "install these four packages").

**Convention: keep internal workspace packages for the boundary, bundle them into one published artifact.**

- Keep `packages/core/` with a **react-less `package.json`** — its dependency graph *mechanically enforces* that the engine has no UI. Import React into `core` and the build breaks. That's the boundary doing its job.
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

`ctl dev` is the reference host, deliberately — day-to-day you develop the package *through* its harness. There is no production `ctl up`: the product isn't deployed from here, it ships via `ctl publish`.

## What's different from the deployed layouts

- The thing in `packages/` is **the product**, not internal shared code (the third `apps/`-vs-`packages/` category — owned by `references/02_decision-tree.md`).
- `apps/web` is a **reference host**, not the deliverable.
- The framework runtime is a **peerDependency**; the package never owns the React instance.
- Versioning + publishing exist; deployment (of the package) does not.
- Config arrives by **injection at mount** (owned by `references/3-app/05-package/02_embeddable-seams.md`), not from a root `.env` the package reads.

## Audit checks

- `apps/web` treated as the deliverable (deployed, documented as "the app") → it's a harness; the package is the product.
- React (or any host-provided runtime) listed under `dependencies` instead of `peerDependencies` → two-Reacts bug risk.
- Multiple internal packages published separately when `noExternal` would ship one artifact → install story leaks the internal split.
- No react-less `core` package (or `core` with a react dep) → the UI-free boundary isn't mechanically enforced.

## Anti-patterns

- Treating `apps/web` as "the app" — it's a harness; the package is the product.
- Bundling the framework runtime into the package instead of `peerDependencies`.
- Publishing four packages when one bundled artifact (`noExternal`) is what consumers want.
- Skipping the headless/UI split — without a react-less `core`, UI leaks into the engine and the boundary rots.

(Seam-specific anti-patterns — baked-in service URLs/secrets, module-level singletons that assume one host — are owned by `references/3-app/05-package/02_embeddable-seams.md`.)

## See also

- `references/1-ecosystem/repo-boundaries.md` — the deployed-vs-distributed decision that routes here.
- `references/3-app/05-package/02_embeddable-seams.md` — embedding seams, IoC config API, per-instance mount model.
- `references/02_decision-tree.md` § "`apps/` vs `packages/` — three categories" — where this fits in the placement model.
- `references/3-app/01-structure-and-stack/02_workspaces-mechanics.md` — the pnpm/turbo workspace mechanics the package + reference-host split reuses.
- `references/handoffs/examples-registry.md` — cite a registered Layout 06 repo if one exists; otherwise propose the pattern on its own merits and flag the absence.
