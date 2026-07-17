# Grouping topology — how `apps/` is arranged, where the workspace roots, where packages sit

One decision cluster, owned here in full: the three named topologies (**flat / plane-grouped / hybrid**) and the rule that picks one (tripwire T1); **workspace rooting** (JS-only repo vs polyglot repo) and its frictions; and **package placement scope** (a package lives at the lowest level that contains all its consumers). Every other file cites these by link — don't restate.

This is a decision file. The multi-frontend **mechanics** (pnpm/turbo config bodies, catalog, `globalEnv`, `ctl` shape) live in `references/3-app/frontend/workspaces-mechanics.md`; package **internals** (what's inside `ui`/`styles`/`types`) in `references/3-app/frontend/shared-packages.md`.

## The three topologies

The default tree lists apps **flat** under `apps/`. That is one of three named topologies — pick one explicitly, ask the user when both fit, and record the choice in the project CLAUDE.md:

| Topology | Shape | When it's right |
|---|---|---|
| **flat** (default) | `apps/{web,admin,api}` + root `packages/` | few apps; shared packages are consumed across planes (or there's only one plane); the workspace-standard shape |
| **plane-grouped** | `apps/server/{api-platform,api-admin}` + `apps/client/{platform,admin}`, frontend-only packages *inside* the client group | 2+ frontends AND (2+ backends OR frontend-only shared packages) — planes exist and the flat listing no longer shows them |
| **hybrid** | plane-grouped apps, `packages/` stays at repo root | grouped planes, but some package crosses them (e.g. `types` consumed by a TS backend) |

```
# plane-grouped
apps/
├── server/
│   ├── api-platform/        # app/ inside, per the backend rules
│   └── api-admin/
└── client/
    ├── package.json         # ← the JS workspace roots HERE in a polyglot repo
    ├── pnpm-workspace.yaml   #   (repo root stays manifest-free — root-and-hygiene.md)
    ├── platform/  admin/    # the frontends
    └── packages/
        ├── ui/  styles/  types/  services/
```

## Decision rule

Two rules drive the pick:

- **Flat until the listing stops communicating.** A grouping layer is the same tripwire reflex as everywhere else — introduce it when planes exist that the flat `apps/` list hides, not before. (Group names are free: `server`/`backend`/`api`, `client`/`frontend`/`web`.)
- **Packages live at the lowest level that contains all their consumers** — the package-scope rule (own section below), applied to topology: frontend-only packages pull the tree toward plane-grouped, a cross-plane package forces hybrid.

**Tripwire T1** — apps in a flat `apps/` that hide planes. Fires when **2+ frontends AND (2+ backends OR frontend-only shared packages)**; the fix is the plane-grouped topology. Cited by ID everywhere else; the number lives here and in the master table (`references/00_altitude-model.md`).

The plane-grouped topology pairs naturally with the admin/user **two-plane split** (`references/3-app/backend/two-plane-split.md`) and forces polyglot **workspace rooting** (next section).

## Workspace rooting — where the JS workspace lives

A JS workspace tool (pnpm + turborepo by default; bun workspaces are a viable alternative) needs a manifest at *its* root. That root is not always the repo root:

| Repo shape | Workspace root | Result |
|---|---|---|
| **JS-only repo** (all apps and packages are JS/TS) | the repo root | root `package.json` (orchestration-only), lockfile, `node_modules/` at root — normal and acceptable |
| **Polyglot repo** (Python/Rust/Go backends + JS frontends) | the **frontend group folder** — `apps/client/` (plane-grouped topology) or the frontend area the repo uses | `package.json`, `pnpm-workspace.yaml`, lockfile, `node_modules/` all live there; **the repo root stays manifest-free** |

Even a JS-only repo's root `package.json` stays orchestration-only — zero runtime deps, no source (`references/2-repo/root-and-hygiene.md` § root manifest rule).

In the polyglot case, `ctl` is the bridge back to the root: `ctl dev` / `ctl build` cd into the workspace root and delegate — mechanics owned by `references/3-app/frontend/workspaces-mechanics.md` § ctl shape. Workspace globs are relative to the workspace root, so the polyglot variant anchors them at the group folder (and the root-rooted variant must exclude non-JS apps); config bodies owned by `references/3-app/frontend/workspaces-mechanics.md`.

Known frictions when the workspace is **not** at the repo root — accept and work around, don't silently fall back to root-rooting:

| Tool | Friction | Resolution |
|---|---|---|
| husky / git hooks | expects to install at the git root | use lefthook at the repo root instead (`references/2-repo/tooling/lefthook.md`) — its commands can `cd` into the workspace |
| changesets / publishing | operates from the workspace root | fine — publishing happens from the workspace root; `ctl publish` wraps the `cd` |
| IDE TS server / ESLint | resolves config upward from open folder | open the workspace folder, or use a multi-root/IDE workspace file |
| CI caching | cache keys reference lockfile path | key on `apps/client/pnpm-lock.yaml` (or the actual path) |

## Package placement scope

**A package lives at the lowest level that contains all of its consumers.** This single rule decides both topology (above) and where each shared package physically sits:

- Frontend-only packages (`ui`, `styles`, `tailwind-config`) → inside the client group (`apps/client/packages/`).
- A package consumed **across planes** (e.g. `types` shared with a TS backend) → repo-root `packages/` — which forces the **hybrid** topology (grouped apps, root `packages/`).
- A frontend-only package parked at the repo root overstates its blast radius; a cross-plane package buried inside the client group hides its consumers.

Package internals (export surface, `~15`-component grouping, tailwind-config wiring) are owned by `references/3-app/frontend/shared-packages.md`.

## Audit checks

- Flat `apps/` while the T1 condition holds (2+ frontends AND (2+ backends OR frontend-only packages)) and no recorded topology choice = finding — propose plane-grouped.
- Polyglot repo with the JS workspace rooted at the repo root = finding — propose group-folder rooting (`references/2-repo/root-and-hygiene.md`).
- A frontend-only package at root `packages/`, or a cross-plane package buried inside the client group = finding — move it to its lowest common consumer.
- An exotic tree with **no** recorded topology variant in CLAUDE.md = finding; a recorded plane-grouped/hybrid choice is conformant.

## Anti-patterns

- Introducing a grouping layer before planes exist that the flat listing hides — grouping for its own sake.
- Falling back to a root-rooted workspace at the first tooling friction — the workarounds above are cheap; the cluttered polyglot root is permanent.
- Rooting `node_modules/` + lockfile at the repo root of a polyglot repo that other ecosystems share.

## See also

- `references/2-repo/00_charter.md` — the L2 charter this decision serves
- `references/2-repo/layouts/02_multi-app-monorepo.md` — the multi-app shape that consumes this topology
- `references/2-repo/root-and-hygiene.md` — root-as-index, orchestration-only root manifest (rooting links back here)
- `references/3-app/frontend/workspaces-mechanics.md` — pnpm/turbo/bun config bodies, catalog, `globalEnv`, `ctl` shape
- `references/3-app/frontend/shared-packages.md` — what lives inside `ui`/`styles`/`types` and the export surface
- `references/3-app/backend/two-plane-split.md` — the admin/user split that pairs with plane-grouped
- `references/00_altitude-model.md` — master tripwire table (T1)
