# Frontend api layer, pages, and feature subdivision — inside `src/`

This file owns the **internals of three `src/` skeleton slots**: `api/` (the single server-communication layer), `pages/` (thin route components), and `features/` (where substance lives, and when it subdivides). It carries the frontend half of tripwire **T3** (feature-folder subdivision) and **T6** (thin `pages/`).

What is *not* here: which folders the skeleton contains, the layer import matrix, `layout/` shells, and workspace-package reconciliation are L3 — owned by `references/3-app/03-web-app/00_app-skeleton.md`. What every *type* placed in these folders looks like (zod-inferred API types, feature-internal types, `packages/types`) is owned by `references/4-feature/03_types-and-contracts.md`. This file states the *mechanisms*; that file states the *placements*.

Applies to every Vite/React app; Next/Astro variants keep the same doctrine with the framework's routing layer in place of `pages/` (`references/3-app/03-web-app/01_framework-variants.md`).

## The api-layer doctrine

**No component, hook, page, or store calls `fetch`/axios directly.** All server communication goes through functions in `api/` (or the workspace `packages/services` equivalent), which own:

- **Endpoint paths** — the only place URL strings exist.
- **The response boundary** — zod schemas (or equivalent) parse every response at the edge, so unvalidated data never enters the app. TS types are *inferred* from those schemas — placement owned by `references/4-feature/03_types-and-contracts.md`.
- **Error normalization** — every failure becomes one app-wide error shape.
- **The query-key vocabulary** — TanStack Query keys (or equivalent) live beside the functions they cache, so key collisions and invalidation stay reviewable in one place.

`api/` is the single place the backend contract is expressed. When the API changes, the diff is localized to `api/` plus the affected features — nothing else.

**Domain-vocabulary mirroring**: internally, `api/` groups by the backend's domain vocabulary (`api/catalog.ts`, `api/access.ts` — or folders when a domain outgrows one file), so the two contract surfaces mirror each other by name. The backend domain names are owned by `references/3-app/02-backend/01_domain-grouping.md`; `api/` follows them, it does not invent a parallel vocabulary.

Enforcement grep (empty output = compliant):

```bash
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src/ | grep -v '^src/api/'
```

## `pages/` vs `features/` (T6)

- `pages/` files are **thin**: route wiring, param parsing, composition of feature components — target **under ~50 lines each (T6)**. Substance well past that line, or fetch/query logic inside a page, obligates moving it into `features/`.
- The `pages/` folder tree **mirrors the URL structure** (`pages/settings/members.tsx` ↔ `/settings/members`), so a URL locates its code by inspection.
- All substance lives in `features/`. The router config imports **pages, never feature internals**.

`pages/` is the frontend instance of principle 4 — the root of the route tree is an index into `features/`, not a runtime.

## The feature-folder subdivision tripwire (T3)

When a feature folder crosses **~10 source files (T3)**, subdivide — by sub-feature (`features/sources/configs/`, `features/sources/runs/`) or by kind within the feature (`pages/`, `dialogs/`, `sections/`) — **whichever axis carries the real seams**. Tests co-locate with what they test through the split. Crossing the threshold obligates the split or a recorded deferral (one line in the project CLAUDE.md), same as every structural tripwire.

This is the frontend twin of the backend feature subdivision in `references/4-feature/01_feature-folders.md`; both planes share the ~10-file threshold and the merge-vs-group discipline.

## Audit checks

- The `fetch`/axios grep above → any hit outside `api/` (or `packages/services`) = finding.
- `pages/` files doing substance (well past ~50 lines, or containing fetch/query logic) = finding (T6).
- Count files per feature folder → **~10+ flat with no recorded deferral = finding (T3)**.
- `api/` internals not mirroring backend domain names (a parallel ad-hoc vocabulary) = drift finding.
- Missing skeleton layers in a grown app (routes importing feature internals because `pages/` doesn't exist; fetch logic inside features because `api/` doesn't exist) → structural finding — owned by `references/3-app/03-web-app/00_app-skeleton.md`.

## Anti-patterns

- Fetch logic inside components "just this once" — the api layer dies by exceptions.
- `pages/` as a second components folder — pages route and compose, nothing else.
- A 30-file flat feature folder — the frontend twin of a backend with a dozen flat feature folders; same reflex, subdivide.
- `api/` files named by UI screen instead of backend domain — the two contract surfaces stop mirroring and drift silently.
- Endpoint URL strings scattered through features — the one-place rule is what makes an API change a localized diff.

## See also

- `references/3-app/03-web-app/00_app-skeleton.md` — the `src/` skeleton these slots belong to, the layer import matrix, `layout/` shells, workspace reconciliation
- `references/4-feature/03_types-and-contracts.md` — where API/feature/store/prop types live (both planes)
- `references/3-app/02-backend/01_domain-grouping.md` — the backend domain vocabulary `api/` mirrors
- `references/4-feature/01_feature-folders.md` — the backend twin: feature shape, seams, subdivision (T3 backend)
- `references/3-app/05-package/00_shared-packages.md` — `packages/services` (the workspace `api/` equivalent) internals and export surface
- `references/4-feature/00_charter.md` — the feature-level charter this reference serves
