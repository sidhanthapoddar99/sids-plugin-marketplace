# Docs integration — hand off to `documentation-guide`

This plugin doesn't generate documentation pages directly. It scaffolds the `docs/` slot and hands off to the `documentation-guide` skill (`/docs-init` and its associated reference set) for everything else.

## What `documentation-guide` is

A separate plugin in this same marketplace. It's the operating manual for the `documentation-template` Astro framework — writing markdown, working with the folder-per-issue tracker, blog posts, configuring `site.yaml` / `navbar.yaml` / `footer.yaml`, themes, anything under `data/`.

It ships:

- **One umbrella skill** (`documentation-guide`) that triages to domain-specific references (writing, docs-layout, blog-layout, issue-layout, settings-layout)
- **Two slash commands** — `/docs-init` (scaffold a new project), `/docs-add-section` (scaffold a section under `data/`)
- **11 CLI wrappers on PATH** — `docs-list`, `docs-show`, `docs-subtasks`, `docs-agent-logs`, `docs-set-state`, `docs-add-comment`, `docs-add-agent-log`, `docs-review-queue`, `docs-check-blog`, `docs-check-config`, `docs-check-section`

When `project-setup` decides docs are in scope, it offloads to `/docs-init` for the bootstrap and points the user at `documentation-guide` for ongoing docs work.

## The 5-section default layout

`/docs-init` scaffolds a project with five top-level sections:

| Section | Folder | Use |
|---|---|---|
| **Home** | `data/pages/` | Landing page, marketing/about |
| **Docs** | `data/user-guide/` (or `dev-docs/`) | User-facing or developer-facing documentation |
| **Issues** | `data/todo/` (or `data/issues/`) | Folder-per-issue tracker — subtasks, comments, agent-logs, state |
| **Blog** | `data/blog/` | Flat `YYYY-MM-DD-<slug>.md` posts |
| **User Guide** | `data/user-guide/` | Optional second docs section (skip if you have one above) |

Sections are configured in `site.yaml`. Adding a new section is `/docs-add-section`.

## Two operating modes

**Consumer mode** (the default for monorepos):

```
<project>/
├── apps/  docker/  …
└── docs/                            # ← the slot
    ├── config/                      # site.yaml, navbar.yaml, footer.yaml
    ├── data/                        # all content
    │   ├── pages/                   # Home
    │   ├── user-guide/              # Docs
    │   ├── blog/
    │   └── todo/                    # Issues
    ├── assets/
    ├── themes/                      # optional
    └── documentation-template/      # FRAMEWORK FOLDER — don't edit
        ├── start                    # ./start dev | build | preview
        └── …
```

**Dogfood mode** — the framework repo *is* the project. Doesn't apply here; we always use consumer mode.

## Bootstrapper handoff

When `/ps-setup` reaches the docs step:

1. Decide whether docs are in scope:
   - In-repo `docs/` (recommended for Topology 02–05, 07, 08)
   - Separate `<product>-docs` repo (Topology 06 polyrepo)
   - None (private tool, no docs needed yet)

2. For in-repo: create `docs/.gitkeep`, then **print** the next step:

   ```
   Docs folder created at docs/.
   Now run: /docs-init
   It will ask for site name, description, repo URL, and scaffold the framework.
   ```

3. Do **not** invoke `/docs-init` directly — chaining slash commands is brittle, and `/docs-init` is interactive.

4. Add to project README:

   ```markdown
   ## Documentation

   Full docs in `docs/`. Run the docs site locally:

   \`\`\`bash
   cd docs/documentation-template
   ./start
   \`\`\`
   ```

5. Add to CLAUDE.md, in the "Tooling" section:

   ```markdown
   ## Tooling — `documentation-guide` plugin

   Issue tracker CLIs (`docs-list`, `docs-show`, `docs-set-state`, etc.) require:

   1. cwd inside `docs/documentation-template/` (so `.env` is found)
   2. Or pass `--tracker <abs-path-to-tracker>` (if this project's tracker is not at the default `data/todo/`)

   See the `documentation-guide` skill for the full operating manual.
   ```

   This tells future agents working in the repo to defer to the documentation-guide skill for docs work.

## How `project-setup` should describe docs to the user

```
Documentation in this repo will use `documentation-template` — an Astro
framework that gives you:

  • One markdown source-of-truth that serves docs, blog, issues, and a home page
  • Built-in issue tracker (folder-per-issue with subtasks/comments/agent-logs)
  • CLI tools for issue management (docs-list, docs-show, docs-set-state, ...)
  • Theme system, light + dark by default

After this bootstrap finishes, run `/docs-init` to scaffold the framework
(it will ask for site name + description + repo URL). Then `cd docs/documentation-template && ./start` brings up the docs site at http://localhost:4321.

For everything documentation-related from then on — writing pages, managing
issues, blog posts, settings — defer to the `documentation-guide` skill;
it has the operating manual.
```

## What documentation-template handles vs what it doesn't

| Handled | Not handled |
|---|---|
| Astro-based static site | Translations / i18n (out of scope) |
| Markdown + frontmatter (title required) | API reference generation (separate problem; use the docs to *embed* generated content) |
| Folder-per-issue tracker | Database-backed issue tracking (use GitHub Issues / Linear for that) |
| Blog with `YYYY-MM-DD-<slug>.md` | Comments on posts (static-site limitation) |
| Light + dark themes | Search (Algolia / pagefind can be added later) |
| Custom layouts via `layouts/` | Server-rendered pages (it's a static site) |

## Polyrepo case (Topology 06)

Each service repo's README points at the docs repo URL. The docs repo itself is initialised separately with `/docs-init`. The aggregator repo's README links to the docs repo too.

Don't `git-subdir`-vendor the docs repo into each service — the deduplication isn't worth the sync overhead.

## What lives in the docs site

Encourage Sid (and any user) to put in `docs/`:

- **Architecture decisions** — `data/<docs-section>/architecture/` with each major decision as a page
- **Design tokens spec** — link from the docs to `apps/<frontend>/src/styles/tokens.css`
- **Issue tracker entries** for each meaningful feature/bug — `data/todo/YYYY-MM-DD-NN-<slug>/`
- **Setup guides for contributors** — README is for getting started; docs are for going deep
- **Per-decision rationale notes** — under an issue's `notes/` folder

## Anti-patterns

- Rolling a docs scaffolder inside `project-setup` — defeats composition; use `/docs-init`
- Forcing a docs site on every project — some tiny tools really don't need one (skip)
- Different docs structures per project — keep documentation-template as the single answer
- Mixing in-repo and separate-repo docs in the same product — pick one
- Hand-syncing content between a docs site and the README — link from README to docs, don't duplicate
- Editing files under `docs/documentation-template/` directly — that's vendored framework code
