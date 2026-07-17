# The repo root contract — root as index, plus hygiene

The repo root is an **index, not a runtime**. It orchestrates (`ctl`, config contracts, README) and links inward; the things that actually run — apps, packages, workspaces — live inside folders. This reference owns that rule, the orchestration-only root-manifest rule, the single-package containment rule (with its recorded exceptions), and the `.gitignore` doctrine.

Workspace rooting — where the JS workspace physically sits, and the tooling frictions that follow — is owned by `references/2-repo/01-layouts/00_grouping-topology.md`; don't restate it here.

## What may exist at root

Config + README + folders + the dispatcher. Concretely: `ctl`, `.mise.toml`, `.env` / `.env.example`, `.gitignore`, `CLAUDE.md`, `README.md`, `LICENSE`, and directories (`apps/`, `docker/`, `scripts/`, `infra/`, `data/`, `docs/`, `.claude/`). **No loose code, no runnable entry file, no app manifest that owns dependencies.** (The one exception: project types whose own tooling demands a root entry — see the exception list below.)

## The root manifest rule — orchestration only

Some ecosystems require a manifest at the workspace root (`package.json` for pnpm/bun workspaces). When one must exist at the repo root, it is **orchestration-only**:

- **Zero runtime dependencies** — this is **tripwire T10** (threshold: 1; master table: `references/00_altitude-model.md`). A runtime dep in a root manifest fires it; the fix is moving the dep into the owning app/package folder. Dev tooling only (turbo, typescript, biome) — and even that stays minimal.
- **No source.** No `src/`, no entry point, nothing importable.
- **Scripts delegate** — `"dev": "turbo dev"`, never a script that *is* the app.

A root manifest that accumulates real dependencies is the first symptom of the root becoming a runtime; audits flag it red. Tooling artifacts the workspace manager creates at its root (`node_modules/`, lockfile) are acceptable *at the workspace root* — which is not always the repo root (owned by `references/2-repo/01-layouts/00_grouping-topology.md`).

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

**Not** blanket-ignored: `.vscode/` — debugger/launch configs are selectively committed (`references/2-repo/05-ctl-scripts-tooling/05_vscode-debugger.md`); `.claude/` — project agent config is committed.

The `data/` pattern (negation must un-ignore directories before it can re-include files):

```gitignore
data/**
!data/**/
!data/**/.gitkeep
```

## Residue & staleness — restructures must finish

A restructure isn't done when the tree moves; it's done when everything that *describes or duplicates* the tree moves with it. The residue classes, all audit findings:

- **Stale self-description** — README / CLAUDE.md still describing the pre-restructure layout (old folder names, old compose paths, old startup commands). Worse than missing docs: an agent or contributor will follow them confidently. Every restructure ends with a docs-vs-tree pass over README, CLAUDE.md, and the docs site.
- **Graveyard directories** — `old/`, `backup/`, `<thing>-v1/` kept "just in case". Git history is the backup; delete them.
- **Retired duplicates** — a superseded docs site, config system, or tool left beside its replacement. Two of a thing = nobody knows which is true; finish the migration and delete.
- **Committed data archives** — datasets, dumps, model weights, zip backups sitting beside code. They belong in gitignored `data/` (runtime state) or external storage, never in the tree.
- **Loose git worktrees / scratch checkouts** inside the repo or beside the product's repos — they read as projects to humans and agents alike. Keep worktrees under a dedicated ignored path (e.g. `.claude/worktrees/`) or outside the project directory entirely.

## Audit checks

- Loose code / entry files at the repo root (no recorded exception) = red finding.
- README / CLAUDE.md describing a layout the tree no longer matches (docs-vs-tree drift) = red finding — actively misleads.
- Graveyard dirs (`old/`, `backup/`, `*-v1/`), retired duplicate systems, committed data archives, or loose worktrees/scratch checkouts = finding each (§ residue above).
- Root `package.json` with runtime `dependencies` = red finding — tripwire T10 crossed (root became a runtime).
- `.env` (any level) not ignored, or `data/` tracked = red finding.
- No `.gitignore`, or one missing an ecosystem that's present in the repo = finding.

(Workspace-rooting audit — polyglot repo rooted at the repo root — is owned by `references/2-repo/01-layouts/00_grouping-topology.md`.)

## Anti-patterns

- `npm init` / `uv init` at the repo root "to get started" — the first commit decides the layout; start inside the folder.
- A root manifest that quietly gains `dependencies` because "it's just one lib" — that's the app moving into the root.
- Copying a maximal gitignore template with 12 ecosystems "to be safe" — unreadable, unauditable; curate.
- Ignoring `.vscode/` and `.claude/` wholesale — they carry committed project config.

## See also

- `references/2-repo/01-layouts/00_grouping-topology.md` — workspace rooting (JS-only vs polyglot), the tooling-friction table, package placement scope
- `references/2-repo/01-layouts/01_single-app.md` — the containment tree for one-app repos
- `references/2-repo/03-env-config/00_env-precedence.md`, `references/2-repo/03-env-config/03_secrets-matrix.md` — what the secrets sections protect
- `references/2-repo/00_index.md` — the repo-level charter this reference serves
