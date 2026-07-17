# Example 06 — embeddable package + reference host (Layout 06)

A worked, anonymized instance of **Layout 06**: the repo's deliverable is a *published package* — here a generic embeddable **flow-editor** (a visual node-graph component external SaaS hosts mount inside their own apps) — plus a react-less `core` engine and a thin `apps/web` reference host used only to develop and demo it. No service is deployed from this repo; the product ships via `ctl publish`.

This file **shows**; it owns no rules. Every part is annotated with the reference that governs it — see the map at the bottom. Product/scope names (`@you/…`, `flow-editor`) are placeholders.

Read alongside:

- `references/2-repo/01-layouts/06_embeddable-package.md` — the repo shape, publishing mechanics, single-artifact delivery, `ctl` shape (the normative layout).
- `references/3-app/05-package/02_embeddable-seams.md` — the embedding seams / IoC config API / per-instance mount model (the normative seam rules).
- `references/1-ecosystem/repo-boundaries.md` — why this is distributed-not-deployed (the decision that routes here).

## The shape in one line

**Two packages for the authors (`flow-editor` UI + react-less `flow-core`), one artifact for the consumers (`@you/flow-editor` with `flow-core` bundled in), and one reference host (`apps/web`) that is never published.**

## Annotated tree

```
flow-editor/                              # workspace root — the PRODUCT is packages/flow-editor
├── package.json                          # private:true, orchestration-only manifest (no runtime deps) — T10
├── pnpm-workspace.yaml                   # workspace globs: packages/*, apps/*  → references/3-app/01-structure-and-stack/02_workspaces-mechanics.md
├── turbo.json                            # build/test pipeline (dev, build, test, publish) → references/3-app/01-structure-and-stack/02_workspaces-mechanics.md
├── ctl                                   # the ONE entrypoint: dev/build/test/publish/clean → 00_script-overview.md
├── scripts/                              # ctl workers (copied verbatim, adapted by deletion — conformance floor)
│   ├── common/{_lib.sh,_select.sh}
│   └── dev/  container/  config/
│
├── packages/
│   ├── flow-editor/                      # ← THE PRODUCT (this is what gets published)
│   │   ├── package.json                  # name "@you/flow-editor"; exports map; peerDeps react; files:["dist"]
│   │   ├── tsup.config.ts                # LIBRARY build (ESM + .d.ts); external react; noExternal @you/flow-core
│   │   ├── src/
│   │   │   ├── index.ts                  # the public API surface — the ONLY entry consumers import
│   │   │   ├── FlowEditor.tsx            # the embeddable React component (mounts one editor instance)
│   │   │   ├── config.ts                 # the SEAM contract (services/storage/theme) → references/3-app/05-package/02_embeddable-seams.md
│   │   │   ├── core/                     # re-exports @you/flow-core for internal use (bundled at publish)
│   │   │   └── ui/                        # React UI layer: nodes, toolbar, panels (primitive-first) → styling-discipline
│   │   ├── tests/                        # unit tests for the component + config wiring
│   │   └── README.md                     # how an EXTERNAL host installs `@you/flow-editor` and mounts it
│   │
│   └── flow-core/                        # react-less engine — the boundary enforcer
│       ├── package.json                  # name "@you/flow-core"; NO react dep → import React ⇒ build breaks
│       ├── src/
│       │   ├── graph.ts                  # headless graph model (nodes/edges, no DOM, no React)
│       │   ├── layout.ts                 # auto-layout math — reusable from a server/CLI too
│       │   └── index.ts
│       └── tests/
│
├── apps/
│   ├── web/                              # ← REFERENCE HOST (dev harness — NOT the product, never published)
│   │   ├── package.json                  # depends on "@you/flow-editor" via workspace:*
│   │   ├── .env.example                  # VITE_* only — throwaway/local demo service URLs → frontend-env-isolation
│   │   ├── vite.config.ts                # ordinary Vite APP bundling (distinct from the package's library build)
│   │   └── src/
│   │       ├── main.tsx                   # mounts <FlowEditor config={localImpls} /> with mock services/storage
│   │       ├── demos/                      # multiple mounts on one page → proves per-instance model
│   │       └── mocks/                      # local storage + auth stubs that fill the seams
│   └── api/                              # OPTIONAL BFF — present ONLY because this demo needs a backend
│       ├── app/                          # flat app/ (run-service, no src/) → references/3-app/02-backend/00_app-skeleton.md
│       │   ├── main.py
│       │   └── core/
│       ├── config.yaml
│       └── README.md
│
├── docker/                              # optional — ONLY the reference host's demo deps (not the product)
│   └── compose.yaml                     # profile-less base for local demo services → 00_docker-overview.md
├── .changeset/                          # changesets: per-package semver bumps + changelog
├── docs/                                # optional in-repo docs → 1-ecosystem/docs-placement.md
├── .claude/  CLAUDE.md                  # recorded variant choices + styling block → handoffs/claude-folder.md
├── README.md  LICENSE
```

Everything under `apps/` exists to develop `packages/flow-editor/`. Delete `apps/` and the product still ships; delete `packages/flow-editor/` and there is no product.

## The published `package.json` (instance)

Concrete instance of the publishing rules owned by `references/2-repo/01-layouts/06_embeddable-package.md` — don't restate them, this only shows a filled-in shape.

```jsonc
// packages/flow-editor/package.json
{
  "name": "@you/flow-editor",
  "version": "1.4.0",
  "type": "module",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.mjs" }
  },
  "files": ["dist"],                                  // ship only build output, not src/
  "peerDependencies": { "react": ">=18", "react-dom": ">=18" },
  "devDependencies": { "react": "^18", "tsup": "^8" }  // react here for dev/build ONLY, not a runtime dep
  // NOTE: @you/flow-core is NOT listed as a dependency — it's bundled in (noExternal) below
}
```

```ts
// packages/flow-editor/tsup.config.ts — library build (contrast apps/web's app bundling)
export default {
  entry: ["src/index.ts"],
  format: ["esm"],
  dts: true,
  external: ["react", "react-dom"],   // peers stay external → host owns the single React instance
  noExternal: ["@you/flow-core"],     // ← engine collapsed into the one published artifact
};
```

Consumers run `npm i @you/flow-editor` and receive one package; `@you/flow-core` never appears in their lockfile. That is the single-artifact-delivery convention (owner: layout 06).

## The seam contract (instance)

The editor never reaches for its own services — the host injects them. Full seam rules (injection, per-instance mount, no baked secrets) are owned by `references/3-app/05-package/02_embeddable-seams.md`; this is just the filled-in shape both hosts satisfy.

```ts
// packages/flow-editor/src/config.ts
export interface FlowEditorConfig {
  services: { apiBaseUrl: string; authToken: () => Promise<string> };  // host owns endpoints + tokens
  storage:  { onSave: (g: Graph) => Promise<void>; open: (id: string) => Promise<Graph> };  // host decides where
  theme?:   "light" | "dark" | TokenOverrides;                          // host controls look → references/3-app/05-package/01_tokens-setup.md
}
```

```tsx
// apps/web (reference host) fills the seams with MOCKS:
<FlowEditor config={{ services: mock.services, storage: mock.storage, theme: "light" }} />

// an external real host (a DIFFERENT repo) fills the SAME contract with production impls:
<FlowEditor config={{ services: host.services, storage: host.saveGraph, theme: host.theme }} />
```

Same contract, two implementations — the package can't tell which host it's in.

## `ctl` shape + publish flow

`ctl` shape is owned by `references/2-repo/01-layouts/06_embeddable-package.md`; this shows the concrete verbs and the publish sequence.

```
ctl dev        # runs apps/web (reference host) with @you/flow-editor hot-linked
ctl build      # LIBRARY build of the packages (tsup → dist/, ESM + .d.ts)
ctl test       # flow-core + flow-editor unit tests, then apps/web e2e
ctl publish    # the release flow below — publishes the PACKAGE, never apps/web
ctl clean
ctl help
```

`ctl publish` sequence (a thin wrapper — no bespoke logic):

1. `changeset` — record the semver bump + changelog entry for `@you/flow-editor` (and `flow-core` if it changed).
2. `changeset version` — apply the bump, regenerate `CHANGELOG.md`.
3. `ctl build` — produce `packages/flow-editor/dist/` with `flow-core` bundled in (`noExternal`).
4. `npm publish --access public` from `packages/flow-editor/` — publishes only the one artifact.
5. `apps/web` and `apps/api` are **never** published — there is no `ctl up prod` for "the product"; distribution *is* publishing.

## Key variants this example fixes

| Axis | This example's pick | Owner (where the choice lives) |
|---|---|---|
| Deployed vs distributed | **distributed** (published package) | `references/1-ecosystem/repo-boundaries.md` |
| `apps/` vs `packages/` category | **published product** in `packages/` (third category) | `references/02_decision-tree.md` |
| Framework runtime | React as **peerDependency** (host owns it) | `references/2-repo/01-layouts/06_embeddable-package.md` |
| Internal boundary vs install story | **two workspace packages, one published artifact** (`noExternal`) | `references/2-repo/01-layouts/06_embeddable-package.md` |
| Engine/UI split | **react-less `flow-core`** + React `ui/` | `references/3-app/05-package/02_embeddable-seams.md` |
| Config delivery | **injected at mount**, no package `.env` | `references/3-app/05-package/02_embeddable-seams.md` |
| Reference-host env | `VITE_*` throwaway URLs, no leaked secrets | `references/2-repo/03-env-config/02_frontend-env-isolation.md` |

## Which references govern each part

| Part of the tree | Governed by |
|---|---|
| Overall repo shape, tree, `ctl`, publishing, single-artifact delivery | `references/2-repo/01-layouts/06_embeddable-package.md` |
| `config.ts` seams, IoC injection, per-instance mount, headless/UI split | `references/3-app/05-package/02_embeddable-seams.md` |
| Why the repo is distributed (routes to Layout 06) | `references/1-ecosystem/repo-boundaries.md` |
| `apps/` vs `packages/` three-category placement | `references/02_decision-tree.md` |
| `pnpm-workspace.yaml`, `turbo.json`, workspace wiring | `references/3-app/01-structure-and-stack/02_workspaces-mechanics.md` |
| `apps/api/app/` flat backend skeleton (optional BFF) | `references/3-app/02-backend/00_app-skeleton.md` |
| `apps/web/.env.example`, `VITE_*` isolation | `references/2-repo/03-env-config/02_frontend-env-isolation.md` |
| `docker/compose.yaml` for demo deps | `references/2-repo/04-docker/00_docker-overview.md` |
| `ctl` + `scripts/` conformance floor | `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md` |
| Root manifest orchestration-only (T10), `.gitignore` | `references/2-repo/02-root-hygiene/00_root-and-hygiene.md` |
| `ui/` primitive-first styling, `theme` token overrides | `references/4-feature/04_styling-discipline.md`, `references/3-app/05-package/01_tokens-setup.md` |
| Recorded variant choices + styling block in CLAUDE.md | `references/handoffs/claude-folder.md` |

## See also

- `references/5-examples/00_index.md` — how to read these examples and the example ↔ layout map.
- `references/handoffs/examples-registry.md` — cite a registered real Layout 06 repo if one exists; never invent one.
