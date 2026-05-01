# Install flow

What happens when you run `/plugin install <plugin>@<marketplace>` (or the equivalent `claude plugin install`).

## The full sequence

1. **Resolve the marketplace reference.** Read the marketplace's `marketplace.json` from the user-level marketplace cache (or fetch if not present). Find the entry matching `<plugin>`. Resolve a version constraint (if pinned in `enabledPlugins` or `dependencies`) to a specific tag.
2. **Fetch the plugin source.** If `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/` is missing, download from the source declared in the marketplace entry (GitHub repo at a specific ref, local path, or HTTPS URL). See [`../04_marketplaces/02_source-types.md`](../04_marketplaces/02_source-types.md) for the source resolution model.
3. **Resolve dependencies.** Recursively for each entry in the plugin's `dependencies[]`. Cross-marketplace deps require the root marketplace's `allowCrossMarketplaceDependenciesOn` to list the dep's marketplace. See [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md).
4. **Compute install set.** Detect range conflicts (intersected version ranges across the dependency closure). Auto-installed deps are tracked separately from user-requested installs — `claude plugin prune` later removes auto-deps no plugin requires.
5. **Validate schemas.** `plugin.json` is checked against Claude Code's schema before activation. Failures abort the install with a specific field error. See [`06_schema-validation.md`](./06_schema-validation.md).
6. **Write the registration boolean.** Set `enabledPlugins[<plugin>@<mkt>] = true` in the active scope's `settings.json` (default: user scope; override with `--scope project|local|user`).
7. **Trigger load.** On the next prompt or after `/reload-plugins`, Claude Code re-scans enabled plugins and registers components.

Steps 1–4 may all run before step 5; if any fails, no boolean is written.

## What "active scope" means

`--scope` (or the absence of it) determines which `settings.json` the boolean lands in:

| `--scope` | File | Default? |
|---|---|---|
| `--scope user` | `~/.claude/settings.json` | **Yes** — default for `claude plugin install` |
| `--scope project` | `<repo>/.claude/settings.json` | Use for the dogfood pattern |
| `--scope local` | `<repo>/.claude/settings.local.json` | Use when you don't want to commit |
| `--scope managed` | (admin path) | For admins; specific subcommands only |

The interactive `/plugin install` UI prompts for the scope. The CLI defaults to user.

## Marketplace ref must be added first

`/plugin install <plugin>@<marketplace>` resolves the marketplace from your **already-added** marketplaces. To install from a marketplace you haven't added:

```
/plugin marketplace add <source>
/plugin install <plugin>@<marketplace-name>
```

The `<marketplace-name>` after `@` is the **name field from the marketplace's manifest**, not the source URL or path. After `marketplace add`, the name becomes the canonical handle.

## Deferred load — boolean ≠ active

Writing the boolean does **not** load the plugin into the current session. The runtime picks up new entries on:

- Session restart, or
- `/reload-plugins` (cheaper — re-reads cache without re-downloading, but doesn't re-evaluate hooks)

This is why the standard install ritual is three steps:

```
/plugin marketplace add <source>
/plugin install <plugin>@<marketplace>
/reload-plugins
```

For brand-new hook plugins, `/reload-plugins` won't pick them up — restart the session.

## Pinning and version resolution

If you want a specific version pinned in `enabledPlugins`, the syntax is documented in the official Claude Code release notes (it varies). The default `enabledPlugins` shape is just `"<plugin>@<mkt>": true` — no version, meaning "follow the marketplace's recommended version".

For dependency version pinning (in a plugin's `plugin.json` `dependencies[]`), see [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md).

## Failure modes

| Failure | Likely cause | Fix |
|---|---|---|
| `Marketplace not found` | Marketplace not added yet, or wrong name | `/plugin marketplace list` to check, then `add` |
| `Plugin not found in marketplace` | Plugin name mismatch with `marketplace.json` | Inspect the marketplace's `plugins[].name` field |
| Schema validation error | Malformed `plugin.json` | Fix the field error and reinstall |
| `Range conflict` | Two plugins require incompatible versions of a dep | Update one or both to compatible ranges |
| `Cross-marketplace dep not allowed` | Root marketplace doesn't allow this dep marketplace | Add to `allowCrossMarketplaceDependenciesOn`, or restructure |
| Hook still missing after install | Hooks load at session start | Restart the session, not just `/reload-plugins` |

The `/plugin` UI's **Errors** tab and `claude plugin list --json` (which exposes a structured `errors` field) are the canonical places to diagnose load failures.

## Method 2: hand-author at scope (no install)

You can skip the marketplace flow entirely and drop capability files directly into `~/.claude/skills/`, `~/.claude/commands/`, etc. — see [`../08_composition-patterns/01_hand-author.md`](../08_composition-patterns/01_hand-author.md). No `enabledPlugins` boolean is involved; the files are loaded at session start as if they were part of a synthetic "user-scope plugin".

This is the right call for one-off, never-shared capabilities. The moment you'd copy the same skill into a second project, that's the signal to package it as a plugin.

## See also

- [`02_activation-and-loading.md`](./02_activation-and-loading.md) — what happens after the boolean is written
- [`../04_marketplaces/02_source-types.md`](../04_marketplaces/02_source-types.md) — the five source forms `marketplace add` accepts
- [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — dependency resolution
- [`../12_cli-and-ui/`](../12_cli-and-ui/00_index.md) — full CLI surface
