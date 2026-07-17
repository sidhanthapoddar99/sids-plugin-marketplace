# Docs placement — one product, one docs home

Owns the L1 decision **where a product's documentation lives** (in-repo `docs/` slot vs a separate `<product>-docs` repo) and the **handoff protocol** to the `agent-ks` documentation plugin. `project-setup` never generates doc pages itself: it decides scope, scaffolds the slot, and hands off. Everything about writing docs, blog posts, the issue tracker, themes, and settings belongs to `agent-ks`.

## The decision

| Choice | When |
|---|---|
| **In-repo `docs/`** (default) | Single-repo product — Layouts 01, 02, 04, 05. One repo → one docs home inside it. |
| **Separate `<product>-docs` repo** | Product spans multiple repos (one docs site can't live in all of them), OR docs release / get contributed to on an independent cadence. In an independently-deployed polyrepo product it also doubles as the **ecosystem hub** — the repo/role map lives here (`references/1-ecosystem/cross-repo-contracts.md` § ecosystem hub). |
| **None** | Private tool with no docs audience yet. Skip; revisit when external consumers appear. |

**Invariant: one product = one docs home.** Never both in-repo and separate for the same product; never per-repo doc fragments that split one product's documentation across repos.

## What `agent-ks` is

A separate plugin (the operating manual for the **agent-knowledge-system** Astro framework). It owns everything after the slot exists: markdown + frontmatter, the folder-per-issue tracker, blog posts, `site.yaml` / `navbar.yaml` / `footer.yaml`, themes, HTML artifacts — anything under `data/`.

It ships:

- **Domain skills** that triage docs work — `agent-ks-docs` (writing, docs/blog layout, settings, themes, images), `agent-ks-issues` (the folder-per-issue tracker), `agent-ks-artifacts` (self-contained HTML report/dashboard pages).
- **Scaffold commands** — `/agent-ks-init` (bootstrap a new project) and `/agent-ks-add-section` (add a top-level section under `data/`).
- **CLI wrappers** for tracker operations (list / show / set-state / add-comment / agent-logs and friends). Exact names and invocation belong to the `agent-ks-issues` skill — defer to it, don't restate here.

When `project-setup` decides docs are in scope, it offloads the bootstrap to `/agent-ks-init` and points the user at `agent-ks` for all ongoing docs work.

## The 5-section default layout

`/agent-ks-init` scaffolds five top-level sections, configured in `site.yaml`:

| Section | Folder | Use |
|---|---|---|
| **Home** | `data/pages/` | Landing page, marketing / about |
| **Docs** | `data/user-guide/` (or `dev-docs/`) | User- or developer-facing documentation |
| **Issues** | `data/todo/` (or `data/issues/`) | Folder-per-issue tracker — subtasks, comments, agent-logs, state |
| **Blog** | `data/blog/` | Flat `YYYY-MM-DD-<slug>.md` posts |
| **User Guide** | `data/user-guide/` | Optional second docs section (skip if covered above) |

Add a new section with `/agent-ks-add-section`.

## Consumer-mode slot

The framework is vendored into the product as a folder; the product supplies only content under `data/` and config. This is the only mode `project-setup` uses.

```
<project>/
├── apps/  docker/  …
└── docs/                            # ← the slot
    ├── config/                      # site.yaml, navbar.yaml, footer.yaml, .env
    ├── data/                        # all content
    │   ├── pages/                   # Home
    │   ├── user-guide/              # Docs
    │   ├── blog/
    │   └── todo/                    # Issues
    ├── assets/
    ├── themes/                      # optional
    └── <framework>/                 # VENDORED FRAMEWORK — don't edit
```

The vendored framework folder is set up by `/agent-ks-init`; treat it as read-only framework code. For running the site locally, defer to the `agent-ks` skill.

## Bootstrapper handoff

When `/ps-setup` reaches the docs step:

1. **Decide scope** using the table above — one product, one docs home. This decision is owned here.
2. **For in-repo:** create `docs/.gitkeep`, then **print** the next step (do not chain into the interactive scaffold):

   ```
   Docs folder created at docs/.
   Now run: /agent-ks-init
   It will ask for site name, description, and repo URL, then scaffold the framework.
   ```

3. **Do not invoke `/agent-ks-init` directly** — chaining slash commands is brittle and it is interactive.
4. **Add a Documentation section to the project README** pointing at `docs/` and how to run the site locally (README contract owned by `references/2-repo/02-root-hygiene/01_readme-three-paths.md`).
5. **Add a Tooling note to CLAUDE.md** telling future agents to defer to `agent-ks` for all docs work, and where the tracker lives (default `data/todo/`; pass an explicit tracker path if it differs). CLAUDE.md template guidance is owned by `references/handoffs/claude-folder.md`.

## How to describe docs to the user

> Documentation in this repo uses the **agent-knowledge-system** Astro framework:
> one markdown source-of-truth serving docs, blog, a built-in folder-per-issue
> tracker, and a home page; CLI tools for issue management; light + dark themes.
> After this bootstrap, run `/agent-ks-init` to scaffold it (site name +
> description + repo URL). From then on defer to the `agent-ks` skill for
> writing pages, managing issues, blog posts, and settings — it has the manual.

## What lives in the docs site

Encourage putting in `docs/`:

- **Architecture decisions** — one page per major decision under the docs section.
- **Design-tokens spec** — link from the docs to the app's `tokens.css` (tokens owned by `references/3-app/05-package/01_tokens-setup.md`); don't duplicate token values into docs.
- **Issue-tracker entries** for each meaningful feature / bug.
- **Contributor setup guides** — README is for getting started, docs are for going deep.
- **Per-decision rationale notes** — under an issue's `notes/` folder.

## What the framework handles vs not

| Handled | Not handled |
|---|---|
| Astro static site, markdown + frontmatter (title required) | i18n / translations |
| Folder-per-issue tracker | Database-backed issue tracking (use GitHub Issues / Linear) |
| Blog (`YYYY-MM-DD-<slug>.md`) | Comments on posts (static-site limitation) |
| Light + dark themes, custom layouts | Server-rendered pages; search (add Algolia / pagefind later) |
| Embedding generated content | Generating API reference (embed it, don't generate here) |

## Polyrepo case (Layout 03)

A dedicated `<product>-docs` repo, initialised separately with `/agent-ks-init`. Each service repo's README links to the docs-repo URL; the aggregator repo's README links there too. **Do not vendor the docs repo into each service** — the dedup isn't worth the sync overhead. Aggregator / repo-shape details: `references/2-repo/01-layouts/03_polyrepo-aggregator.md`.

## Audit checks

- Product docs duplicated across repos, or a docs site with no clear single home = finding.
- In-repo `docs/` **and** a separate docs repo for the same product = finding (pick one).
- Per-repo doc fragments for one product = finding.
- README content hand-synced with the docs site instead of linking to it = finding.
- Edits inside the vendored framework folder = finding (that's framework code).

## Anti-patterns

- Building a docs scaffolder inside `project-setup` — defeats composition; use `/agent-ks-init`.
- Forcing a docs site on every project — tiny tools may not need one; skip.
- A different docs structure per project — agent-knowledge-system is the single answer.

## See also

- L1 decision index and invariants: `references/1-ecosystem/00_index.md`.
- Sharing / vendoring ranking (why not to vendor the docs repo): `references/1-ecosystem/cross-repo-contracts.md`.
- README contract: `references/2-repo/02-root-hygiene/01_readme-three-paths.md`. CLAUDE.md template: `references/handoffs/claude-folder.md`.
