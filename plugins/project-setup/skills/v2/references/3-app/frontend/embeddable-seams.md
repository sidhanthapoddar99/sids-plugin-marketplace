# Embeddable package — seams, IoC config API, per-instance mounts

Owns the **runtime architecture** of a package whose deliverable is embedded in an *external host* rather than deployed as a service: the embedding seams (inversion of control), the config/props contract the host fills, the reference-vs-real-host distinction *as it drives the seams*, and the per-instance mount model. This is the how-it's-wired half of Layout 06.

The **repo shape**, the tree, **publishing mechanics**, and **single-artifact delivery** are owned by `references/2-repo/layouts/06_embeddable-package.md`. The **when** — a repo is distributed-not-deployed — is owned by `references/1-ecosystem/repo-boundaries.md`. This file assumes those decisions are made and covers only the seams.

## Reference host vs real host (who fills the seams)

The same package runs in two kinds of host, filling one contract with two implementations:

| | Reference host (`apps/web`, in *this* repo) | Real host (a *different*, external repo) |
|---|---|---|
| Role | dev harness — see the package work, write stories, run e2e | the actual consumer; ships the product to users |
| Owns | local/throwaway service impls | production services, auth, storage, the React instance |
| Published? | never | yes (it's their app) |
| Fills the seams with | mock/local implementations | real implementations |

Same `config` contract, two implementations. The package can't tell which host it's in — that's the goal. The mistake to avoid: thinking the reference host *is* the app. It's a stand-in so you can develop the real product (the package). The repo-shape framing of this distinction (needed to read the tree) is owned by layout 06; here it exists to explain who supplies each seam.

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

## Headless engine / UI split (the seam that keeps the engine host-agnostic)

For SDKs with logic + UI, split into a **react-less headless engine** and a **React UI layer** so the engine can be filled and reused by hosts that aren't React at all:

- `packages/core/` (or `src/core/`) — the engine, kept react-less by contract.
- `packages/<pkg>/` (or `src/ui/`) — the React component that wraps the engine and renders it.

This lets the engine be consumed headlessly (server, CLI, a non-React host) while the UI layer stays optional. The **packaging** side of this split — the react-less `package.json` that mechanically enforces the boundary, and bundling `core` into one published artifact (`noExternal`) — is owned by `references/2-repo/layouts/06_embeddable-package.md` § single-artifact delivery.

## Anti-patterns

- A `.env` inside the published package — config must be host-injected, not read by the package.
- Baking service URLs / secrets / save-locations into the package — they're seams, filled by the host.
- Module-level singletons — break the per-instance mount model.
- Skipping the headless/UI split — UI leaks into the engine; the engine stops being reusable headlessly.

(Repo-shape + packaging anti-patterns — treating the reference host as the product, peerDependency mistakes — are owned by `references/2-repo/layouts/06_embeddable-package.md`.)

## See also

- `references/2-repo/layouts/06_embeddable-package.md` — the repo shape, tree, publishing mechanics, single-artifact delivery, and `ctl` shape.
- `references/1-ecosystem/repo-boundaries.md` — the deployed-vs-distributed decision that routes a repo to Layout 06.
- `references/02_decision-tree.md` § "`apps/` vs `packages/` — three categories" — the placement model (deployable / internal lib / published product).
- `references/3-app/frontend/workspaces-mechanics.md` — the pnpm/turbo workspace mechanics the package + reference-host split reuses.
- `references/3-app/frontend/tokens-setup.md` — the `theme` seam maps onto the token system when the host passes token overrides.
- `references/2-repo/env-and-config/frontend-env-isolation.md` — for the reference host's own env, the usual `VITE_*` rules still apply.
