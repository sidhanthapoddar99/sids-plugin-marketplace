# Docs integration — hand off to `/docs-init`

This plugin doesn't generate documentation pages directly. It scaffolds the `docs/` slot and then calls `/docs-init` from the `documentation-guide` plugin to populate it.

## When `/ps-setup` reaches the docs step

After the rest of the layout is decided, ask:

> Documentation:
> - **In-repo `docs/`** (recommended for monorepo) — `/docs-init` from documentation-guide plugin
> - **Separate `<product>-docs` repo** (Topology 06 polyrepo) — confirm repo name
> - **None** (private tool, no docs needed yet)

For in-repo, the bootstrapper:

1. Creates `docs/` directory
2. Prints: "Now run `/docs-init` to scaffold the documentation-template site here."

It does **not** invoke `/docs-init` directly — the user runs it. This is because `/docs-init` is interactive (asks site name, description, repo URL), and chaining slash commands is brittle.

## Why hand off, not roll our own

- **documentation-guide is already the source of truth** for docs structure (5 sections — Home, Docs, Issues, Blog, User Guide; settings.json schema; folder conventions)
- **No duplication** — fixing a docs convention in one plugin updates everyone
- **Composition is the right pattern** — plugins in the same marketplace should cooperate, not overlap

## What the bootstrapper does set up

Even before `/docs-init`, the bootstrapper can drop:

- `docs/.gitkeep` (so the empty folder lands in git)
- A line in the project README pointing at `docs/`
- A reminder in CLAUDE.md that docs use `documentation-template`

## Multi-repo case (Topology 06)

When the project is polyrepo with separate docs repo:

- This bootstrapper does NOT create `docs/` in each service repo
- Each service repo's README points at the docs repo's URL
- The docs repo itself is initialised separately with `/docs-init`
- Aggregator repo's README aggregates the pointers

## When `documentation-guide` plugin is not installed

If the user runs `/ps-setup` without `documentation-guide` available:

- Skip the docs offer entirely, OR
- Print a one-line note: "Install `documentation-guide` from sids-plugin-marketplace if you want a docs site; otherwise add docs manually."

## Linking from README

```markdown
## Documentation

Full design docs in `docs/`. Run the docs site locally:

\`\`\`bash
cd docs/documentation-template
./start
\`\`\`
```

The `start` script is a `documentation-guide` artefact — don't invent it here.

## Anti-patterns

- Rolling a docs scaffolder inside this plugin — defeats composition
- Forcing a docs site on every project — some really don't need one
- Different docs structures per project — keep documentation-guide as the single answer
- Mixing in-repo and separate-repo docs in the same product — pick one
