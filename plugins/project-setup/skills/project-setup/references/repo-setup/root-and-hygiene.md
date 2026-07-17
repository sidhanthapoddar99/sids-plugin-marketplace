# The repo root contract — root as index, plus hygiene

The repo root is an **index, not a runtime**. It orchestrates (`ctl`, config contracts, README) and links inward; the things that actually run — apps, packages, workspaces — live inside folders. This reference owns that rule, the workspace-rooting decision that follows from it, the single-package containment rule, and the `.gitignore` doctrine.

## What may exist at root

Config + README + folders + the dispatcher. Concretely: `ctl`, `.mise.toml`, `.env` / `.env.example`, `.gitignore`, `CLAUDE.md`, `README.md`, `LICENSE`, and directories (`apps/`, `docker/`, `scripts/`, `infra/`, `data/`, `docs/`, `.claude/`). **No loose code, no runnable entry file, no app manifest that owns dependencies.** (The one exception: project types whose own tooling demands a root entry — see the exception list below.)

## The root manifest rule — orchestration only

Some ecosystems require a manifest at the workspace root (`package.json` for pnpm/bun workspaces). When one must exist at the repo root, it is **orchestration-only**:

- **Zero runtime dependencies.** Dev tooling only (turbo, typescript, biome) — and even that stays minimal.
- **No source.** No `src/`, no entry point, nothing importable.
- **Scripts delegate** — `"dev": "turbo dev"`, never a script that *is* the app.

A root manifest that accumulates real dependencies is the first symptom of the root becoming a runtime; audits flag it red. Tooling artifacts the workspace manager creates at its root (`node_modules/`, lockfile) are acceptable *at the workspace root* — which is not always the repo root:

## Workspace rooting — where the JS workspace lives

| Repo shape | Workspace root | Result |
|---|---|---|
| **JS-only repo** (all apps and packages are JS/TS) | the repo root | root `package.json` (orchestration-only), lockfile, `node_modules/` at root — normal and acceptable |
| **Polyglot repo** (Python/Rust/Go backends + JS frontends) | the **frontend group folder** — `apps/client/` (plane-grouped topology) or the frontend area the repo uses | `package.json`, `pnpm-workspace.yaml`, lockfile, `node_modules/` all live there; **the repo root stays manifest-free** |

In the polyglot case, `ctl` is the bridge back to the root: `ctl dev` / `ctl build` change into the workspace root and delegate (`turbo dev --filter=…`), so day-to-day commands never depend on where the workspace physically sits. Workspace globs adjust accordingly (see `references/architecture/frontend/multi-frontend-workspaces.md` § rooting).

Known frictions when the workspace is not at the repo root — accept and work around, don't silently fall back to root-rooting:

| Tool | Friction | Resolution |
|---|---|---|
| husky / git hooks | expects to install at the git root | use lefthook at the repo root instead (`references/repo-setup/tooling/lefthook.md`) — its commands can `cd` into the workspace |
| changesets / publishing | operates from the workspace root | fine — publishing happens from the workspace root; `ctl publish` wraps the `cd` |
| IDE TS server / ESLint | resolves config upward from open folder | open the workspace folder, or use a multi-root/IDE workspace file |
| CI caching | cache keys reference lockfile path | key on `apps/client/pnpm-lock.yaml` (or the actual path) |

## Single-package repos — contain the package

When the repo's deliverable is one package (a library, CLI, SDK), the package still lives in its own top-level folder — `./<name>/` with the manifest, `src/`, tests inside (Layout 01) — and the root keeps only the index. Running happens *in* the folder; `ctl` (or a small `dev` wrapper) links it to the root.

**Documented exceptions** — ecosystems where the manifest genuinely must sit at the repo root because external tooling or contributors resolve the repo *as* the package:

- **Editor extensions** (e.g. VS Code extensions) — the packaging tool expects the manifest at the repo root.
- **A pure open-source package repo** where the repo *is* the published artifact and external contributors expect the ecosystem-standard root manifest.

Taking an exception is a **recorded choice**: one line in the project CLAUDE.md ("root-manifest layout: <reason>"), so audits treat it as the chosen variant instead of drift. Default remains containment.

## `.gitignore` doctrine

One committed `.gitignore` at the repo root, **curated per-ecosystem at bootstrap** — the sections the repo actually needs, not a 500-line kitchen-sink template. Snippet: `assets/snippets/env/gitignore.template`. The categories:

1. **Secrets & local config** — all `.env*` except `.env.example` (root *and* per-app: frontends carry their own pair), `config.local.yaml`. A tracked `.env` is a red audit finding.
2. **Runtime state** — `data/**` with the `.gitkeep` negation pattern (below).
3. **Ecosystem artifacts** — only the sections for ecosystems present: Python (`__pycache__/`, `.venv/`, tool caches), JS (`node_modules/`, `dist/`, `.turbo/`), etc. New ecosystem joins the repo → its section joins the file.
4. **Logs & OS junk** — `*.log`, `.DS_Store`.

**Not** blanket-ignored: `.vscode/` — debugger/launch configs are selectively committed (`references/repo-setup/tooling/vscode-debugger.md`); `.claude/` — project agent config is committed.

The `data/` pattern (negation must un-ignore directories before it can re-include files):

```gitignore
data/**
!data/**/
!data/**/.gitkeep
```

## Audit checks

- Loose code / entry files at the repo root (no recorded exception) = red finding.
- Root `package.json` with runtime `dependencies` = red finding (root became a runtime).
- Polyglot repo with the JS workspace rooted at the repo root = finding — propose group-folder rooting.
- `.env` (any level) not ignored, or `data/` tracked = red finding.
- No `.gitignore`, or one missing an ecosystem that's present in the repo = finding.

## Anti-patterns

- `npm init` / `uv init` at the repo root "to get started" — the first commit decides the layout; start inside the folder.
- A root manifest that quietly gains `dependencies` because "it's just one lib" — that's the app moving into the root.
- Copying a maximal gitignore template with 12 ecosystems "to be safe" — unreadable, unauditable; curate.
- Ignoring `.vscode/` and `.claude/` wholesale — they carry committed project config.
- Falling back to root-rooted workspace at the first tooling friction — the workarounds above are cheap; the cluttered root is permanent.

## See also

- `references/repo-setup/layouts/01_single-app.md` — the containment tree for one-app repos
- `references/repo-setup/layouts/02_multi-app-monorepo.md` — grouping topology (where the frontend group folder comes from)
- `references/architecture/frontend/multi-frontend-workspaces.md` — workspace mechanics + rooting globs
- `references/repo-setup/env-and-config/env-precedence.md`, `secrets-matrix.md` — what the secrets sections protect
- `references/levels/02_repo.md` — the repo-level charter this reference serves
