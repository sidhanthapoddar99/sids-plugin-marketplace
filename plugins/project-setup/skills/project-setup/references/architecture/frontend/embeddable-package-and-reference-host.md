# Embeddable package + reference host

The mechanics behind Topology 09: when the repo's deliverable is a **published package** (UI component / SDK / headless engine) that an *external host* mounts, not a service you deploy. This doc covers the embedding seams (inversion of control), the reference-vs-real host distinction, the per-instance mount model, and the publishing details deployed topologies never need.

Read `references/repo-setup/topologies/09_embeddable-package-and-reference-host.md` for the topology and tree; this is the how-to for the seams and the build.

## Reference host vs real host

| | Reference host (`apps/web`, in *this* repo) | Real host (a *different*, external repo) |
|---|---|---|
| Role | dev harness — see the package work, write stories, run e2e | the actual consumer; ships the product to users |
| Owns | local/throwaway service impls | production services, auth, storage, the React instance |
| Published? | never | yes (it's their app) |
| Fills the seams with | mock/local implementations | real implementations |

Same `config` contract, two implementations. The package can't tell which host it's in — that's the goal. The mistake to avoid: thinking the reference host *is* the app. It's a stand-in so you can develop the real product (the package).

## Embedding seams — inversion of control

The package **declares what it needs**; the **host decides how**. The package never reaches out for its own services, storage, or theme — they're injected at mount through a config/props API.

```ts
// the seam contract (packages/<pkg>/src/config.ts)
export interface EmbedConfig {
  // SERVICES — endpoints/clients the host owns. Never baked into the package.
  services: {
    apiBaseUrl: string;
    authToken: () => Promise<string>;     // host supplies tokens; package never stores secrets
  };
  // STORAGE — the host decides WHERE things persist. Package only calls hooks.
  storage: {
    onSave: (doc: Doc) => Promise<void>;
    open: (id: string) => Promise<Doc>;
    cache?: KVLike;                        // optional caching hook, host-provided
  };
  // RUNTIME / THEME — host controls look + behaviour.
  theme?: "light" | "dark" | TokenOverrides;
  features?: Partial<FeatureFlags>;
}
```

```tsx
// host mounts it (reference host OR external real host — identical call shape):
<Editor config={{
  services: { apiBaseUrl: "/api", authToken: host.getToken },
  storage:  { onSave: host.saveDoc, open: host.loadDoc },
  theme:    host.theme,
}} />
```

What this buys you:

- **Secrets and "where saves go" are never baked in.** They arrive via `config`. The package ships with no `.env` of its own. (Contrast the deployed model where a service reads a root `.env`.)
- **No hidden coupling.** Everything the package depends on is visible in the `config` type. Swap a host, swap the impls — nothing inside the package changes.
- **The reference host and real host differ only in the impls they pass.**

## Per-instance mount model (Google-Workspace-style)

The same package may mount **many times on one page**, each instance configured independently — different `apiBaseUrl`, different document, different theme. Design for this from the start:

- **No module-level singletons** that assume a single host or single document. State lives per-instance (per React tree / per config), not in module scope.
- Each mount gets its own `config`; two editors on a page can talk to two different backends.
- Cleanly tear down on unmount — no leaked global listeners, intervals, or caches keyed by a phantom "the one instance".

If the package assumes "there is one of me and one host", it'll break the moment a real host embeds two instances.

## Headless engine / UI split (boundary enforcement)

For SDKs with logic + UI, split into a **react-less headless engine** and a **React UI layer**:

- `packages/core/` (or `src/core/`) — the engine. Its `package.json` has **no `react` dependency**. That dependency graph *mechanically enforces* UI-free: import React into `core` and the build breaks. The boundary isn't a comment, it's the dependency manifest.
- `packages/<pkg>/` (or `src/ui/`) — the React component that wraps the engine and renders it.

This lets the engine be reused headlessly (server, CLI, a non-React host) while the UI layer stays optional.

## Publishing mechanics

A published package is built and versioned differently from a deployed app.

### `package.json` for a published package

```jsonc
{
  "name": "@you/editor",
  "version": "1.4.0",
  "type": "module",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.mjs" }
  },
  "files": ["dist"],                                  // only ship the build output
  "peerDependencies": { "react": ">=18", "react-dom": ">=18" },
  "devDependencies": { "react": "^18", "tsup": "^8" } // react here only for dev/build
}
```

- **`exports`** — declare public entry points; stop consumers deep-importing internals (which become breaking changes when you refactor).
- **`files`** — ship `dist/` only, not `src/`.
- **`peerDependencies` for React** (and any host-owned runtime): the **host owns the single React instance**. Bundling your own React causes "invalid hook call / two copies of React" bugs. React appears in `devDependencies` so your own build/tests work, but it's *not* a runtime `dependency`.

### Library build tooling

Use a **library bundler** (`tsup`, `rollup`, or `vite build --lib`) that emits ESM + `.d.ts` for consumption — **not** app bundling. This is distinct from how you build the reference host (`apps/web`), which uses ordinary Vite app bundling. Two build modes in one repo, for two different outputs.

```ts
// packages/editor/tsup.config.ts
export default {
  entry: ["src/index.ts"],
  format: ["esm"],
  dts: true,
  external: ["react", "react-dom"],   // peer deps stay external
  noExternal: ["@you/core"],          // ← bundle the internal engine in (see below)
};
```

### Versioning + publishing

- **Semver** + a changelog. **Changesets** work well in a workspace (per-package version bumps + changelog generation).
- `ctl publish` wraps version bump + `npm publish` (or PyPI for a Python engine). The **reference host is never published**.
- There is no "deploy" of the product from this repo — distribution *is* publishing.

## Single-artifact delivery (named convention)

You want a clean internal boundary **and** a one-line install for consumers. These pull in opposite directions; resolve them like this:

> **Keep internal workspace packages for the boundary; bundle them into one published artifact.**

- Keep `packages/core/` as a separate workspace package with a **react-less `package.json`** — the boundary that keeps the engine UI-free (above).
- At publish time, **bundle `core` into the published package** instead of listing it as an external runtime dependency — e.g. tsup `noExternal: ["@you/core"]`, or rollup equivalent. The internal split disappears from the consumer's view.

Result: **multiple workspace packages for the authors, one package for the consumers.** They `npm i @you/editor` and get everything; they never see `@you/core`. Boundary preserved, install story simple. This is a reusable decision the skill can hand out directly.

## Anti-patterns

- Bundling React instead of `peerDependencies` — the canonical two-Reacts failure.
- A `.env` inside the published package — config must be host-injected, not read by the package.
- Baking service URLs / secrets / save-locations into the package — they're seams, filled by the host.
- Module-level singletons — break the per-instance mount model.
- Treating the reference host (`apps/web`) as the product — it's a harness.
- Publishing N internal packages when consumers want one (`noExternal` to collapse them).
- No `exports` map — consumers deep-import internals, every refactor is a breaking change.
- Skipping the headless/UI split — UI leaks into the engine; the engine stops being reusable headlessly.

## Cross-references

- `references/repo-setup/topologies/09_embeddable-package-and-reference-host.md` — the topology + tree + `ctl` shape.
- `references/00_decision-tree.md` § "`apps/` vs `packages/` — three categories" — placement model (deployable / internal lib / published product).
- `references/01_question-flow.md` Q3a — the deployed-vs-distributed question that routes here.
- `references/architecture/frontend/multi-frontend-workspaces.md` — the pnpm/turbo workspace mechanics reused for the package + reference-host split.
- `references/repo-setup/env-and-config/frontend-env-isolation.md` — for the reference host's own env, the usual `VITE_*` rules still apply.
