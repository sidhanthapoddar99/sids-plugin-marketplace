---
title: Soft Fork and Upstream Tracking
description: A third option besides depending or hand-authoring — vendor another plugin's skills/agents into your own with a provenance manifest that tracks upstream changes
---

# Soft Fork and Upstream Tracking

The two obvious options for using another plugin's content are:

1. **Depend on it** — declare a `dependencies` entry, both plugins coexist, you reference upstream skills cooperatively in your prose
2. **Hand-author from scratch** — original content in your plugin, no relationship to upstream

There's a third pattern that sits between them: **soft fork with upstream tracking**. You copy upstream content into your plugin (so it lives in your namespace, ships in your install, and you can edit it freely), but you keep a *provenance manifest* that records where each piece came from, when you last synced it, and what local edits you've made. A small bit of tooling tells you when upstream has changed, and you decide whether to merge.

This is how OS distributions vendor third-party libraries, how Go projects use vendored modules, and how `chromium` keeps its v8 copy honest. Same idea applies here.

## When to soft-fork

| Situation | Soft-fork | Depend | Hand-author |
|---|---|---|---|
| Upstream content is good but stale, you'd rewrite anyway | ✅ best fit | ❌ stuck with stale | ⚠️ ignores prior art |
| You want everything in *your* plugin's namespace | ✅ | ❌ upstream's namespace | ✅ but no baseline |
| You want to edit descriptions for triggering control | ✅ | ❌ can't edit upstream | ✅ |
| Cross-marketplace allowlist friction | ✅ none | ❌ requires opt-in | ✅ none |
| Single install, single namespace for users | ✅ | ❌ two installs | ✅ |
| Upstream is fresh, well-maintained, evolves fast | ❌ maintenance treadmill | ✅ free updates | ❌ ignores prior art |
| You'd contribute fixes back upstream | ❌ harder to PR | ✅ natural | n/a |
| Net-new content with no upstream | n/a | n/a | ✅ |

**Tilt toward soft-forking when**: upstream is stale, you're going to rewrite anyway, you want one namespace, and the cross-marketplace allowlist isn't worth the friction.

**Tilt toward depending when**: upstream is fresh, well-maintained, and your plugin only adds *net-new* content.

**Tilt toward hand-authoring when**: there's no upstream worth borrowing from.

You can mix all three within a single plugin — soft-fork some skills, write originals for others, depend on a different plugin for an MCP server you can't replicate.

## What a soft-fork plugin looks like on disk

```
my-plugin/
├── .claude-plugin/plugin.json
├── README.md                        ← user-facing, includes the PROVENANCE table
├── LICENSE                          ← your plugin's license
│
├── .upstream/                       ← provenance & licensing for vendored content
│   ├── manifest.json                ← machine-readable provenance per item
│   ├── LICENSE-plugin-dev           ← upstream LICENSE files preserved
│   └── diffs/                       ← optional, holds 3-way diffs awaiting human merge
│       └── skills-hook-development.upstream.md
│
├── skills/
│   ├── hook-development/SKILL.md    ← soft-imported from plugin-dev, locally improved
│   ├── marketplace-authoring/SKILL.md   ← in-house original
│   └── plugin-dependencies/SKILL.md ← in-house original
│
├── agents/
│   ├── plugin-validator.md          ← soft-imported, extended
│   └── release-manager.md           ← in-house original
│
├── bin/
│   ├── pf-upstream-status           ← reports drift
│   ├── pf-upstream-sync             ← merges or marks for review
│   └── pf-upstream-log              ← append-only sync history
│
└── hooks/hooks.json                 ← SessionStart hook warns on stale items
```

Two key conventions:

- **`.upstream/`** holds provenance metadata and license attribution for vendored content. Not loaded by the plugin runtime; it's purely authoring discipline.
- **`README.md`** at the plugin root surfaces the PROVENANCE table (see below) so consumers — and you, six months from now — can see at a glance which skills are yours and which were borrowed.

## The provenance manifest

`.upstream/manifest.json` records one entry per vendored item. Both the file path *inside your plugin* (`skills/hook-development/SKILL.md`) and the *upstream path it came from* are tracked, so syncing tools can correlate them.

```json
{
  "$schema": "https://example.com/upstream-manifest.schema.json",
  "sources": {
    "plugin-dev": {
      "repo": "https://github.com/anthropics/claude-plugins-official",
      "default_ref": "main",
      "license": "Apache-2.0",
      "license_file": ".upstream/LICENSE-plugin-dev"
    }
  },
  "items": {
    "skills/hook-development/SKILL.md": {
      "source": "plugin-dev",
      "upstream_path": "plugins/plugin-dev/skills/hook-development/SKILL.md",
      "last_synced_sha": "2438937e",
      "last_synced_date": "2026-04-30",
      "local_modified": true,
      "local_modified_date": "2026-04-30",
      "notes": "Added prompt-based hook section, $CLAUDE_ENV_FILE, hot-swap limitation, plugin hooks.json wrapper format"
    },
    "skills/mcp-integration/SKILL.md": {
      "source": "plugin-dev",
      "upstream_path": "plugins/plugin-dev/skills/mcp-integration/SKILL.md",
      "last_synced_sha": "2438937e",
      "last_synced_date": "2026-04-30",
      "local_modified": true,
      "local_modified_date": "2026-04-30",
      "notes": "Added WebSocket type, OAuth flow detail, /mcp UI command, full tool naming format"
    },
    "agents/plugin-validator.md": {
      "source": "plugin-dev",
      "upstream_path": "plugins/plugin-dev/agents/plugin-validator.md",
      "last_synced_sha": "82d04123",
      "last_synced_date": "2026-04-30",
      "local_modified": true,
      "local_modified_date": "2026-04-30",
      "notes": "Extended to validate dependencies, userConfig, monitors, themes manifest fields"
    }
  }
}
```

Per-item fields:

| Field | Purpose |
|---|---|
| `source` | Key into `sources` — which upstream this came from |
| `upstream_path` | Path relative to upstream repo root |
| `last_synced_sha` | Upstream commit SHA at last sync (12-char prefix is enough) |
| `last_synced_date` | When you last pulled from upstream |
| `local_modified` | `true` if you've edited the file since the last sync. Auto-sync skips these |
| `local_modified_date` | When local edits were made (for log/audit) |
| `notes` | What you changed and why. Required when `local_modified: true` for Apache 2.0 attribution and for your own future understanding |

Items not listed in this manifest are assumed to be **in-house originals** with no upstream relationship.

## The unified PROVENANCE table (in your README)

This is the table you put at the top of your plugin's `README.md` — readable for humans, auto-generated from `manifest.json` by your tooling. It answers "where did this come from, and is it current?" at a glance.

```markdown
## Plugin contents

| Component | Type | Origin | Local edited | Upstream sync | Drift | License |
|---|---|---|---|---|---|---|
| `skill-development` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `hook-development` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `mcp-integration` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `plugin-structure` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `plugin-settings` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `agent-development` | skill | soft-import: plugin-dev | — | 2026-04-30 (`ce721c1`) | up-to-date | Apache-2.0 |
| `command-development` | skill | soft-import: plugin-dev | — | 2026-04-30 (`6b70f99`) | up-to-date | Apache-2.0 |
| `marketplace-authoring` | skill | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `plugin-dependencies` | skill | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `plugin-lifecycle` | skill | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `extended-capabilities` | skill | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `agent-creator` | agent | soft-import: plugin-dev | — | 2026-04-30 (`82d0412`) | up-to-date | Apache-2.0 |
| `plugin-validator` | agent | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`82d0412`) | up-to-date | Apache-2.0 |
| `skill-reviewer` | agent | soft-import: plugin-dev | — | 2026-04-30 (`82d0412`) | up-to-date | Apache-2.0 |
| `release-manager` | agent | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `/create-plugin` | command | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`6b70f99`) | up-to-date | Apache-2.0 |
| `/pf-release` | command | **in-house** | 2026-04-30 | — | n/a | <your license> |
```

### Reading the table

| Column | Means |
|---|---|
| **Component** | Skill / agent / command / etc. as it appears in Claude Code |
| **Type** | `skill`, `agent`, `command`, `hook`, `monitor`, `lsp`, `mcp`, etc. |
| **Origin** | `in-house` (original) or `soft-import: <source-name>` |
| **Local edited** | Last time you edited the file locally. `—` if never modified after import |
| **Upstream sync** | Last time you pulled from upstream + the SHA you synced to. `—` for in-house items |
| **Drift** | `up-to-date`, `behind by N commits`, `behind + needs review`, or `n/a` for in-house |
| **License** | The license that applies — your plugin's license for in-house, upstream's for soft-imports |

### Status legend

- **up-to-date** — local synced SHA matches upstream HEAD (or your tracked ref)
- **behind by N commits** — upstream has moved forward, no local edits, safe to auto-sync
- **behind + needs review** — upstream has moved AND you have local edits; requires a 3-way merge
- **n/a** — in-house item, no upstream to track

## Tooling pattern: three small bin scripts

Pick a 2-3 character namespace prefix for your wrappers (e.g., `pf-` for "plugin-forge" or whatever you call your plugin). Drop these in `bin/`:

### `pf-upstream-status`

For each item in `manifest.json`:

1. Hit the GitHub API for the latest commit on `upstream_path` at the source's tracked ref
2. Compare to `last_synced_sha`
3. Print a status line per item

Output:

```
skills/hook-development/SKILL.md     up-to-date (synced 0d ago)
skills/mcp-integration/SKILL.md      behind 3 commits (locally modified — review needed)
skills/plugin-structure/SKILL.md     behind 1 commit (clean — auto-syncable)
agents/agent-creator.md              up-to-date (synced 0d ago)
```

Add `--json` for machine-readable output (good for the SessionStart hook).

### `pf-upstream-sync [--auto] [--dry-run] [--item <path>]`

For each behind item:

- If `local_modified: false` and `--auto`: fetch upstream, overwrite local, update `last_synced_sha` and `last_synced_date`
- If `local_modified: true`: fetch upstream into `.upstream/diffs/<path>.upstream.md`, generate a 3-way diff against the previously synced version, mark as needing review. Don't touch the local file
- `--item <path>` runs sync for one specific item. Useful when you've manually merged a tricky one and want to record the new SHA

After every sync, regenerate the README's PROVENANCE table from `manifest.json`.

### `pf-upstream-log`

Append-only record of every sync operation: timestamp, item, old SHA → new SHA, decision (auto-merged / human-merged / deferred). Lets you audit what happened and when.

## Automating the staleness check

Two low-effort hooks tie everything together:

### SessionStart hook

A small script that runs `pf-upstream-status --json` and counts items not `up-to-date`. If any are behind, it injects a one-line system reminder for the model:

```
[plugin-forge] 3 vendored items are behind upstream — run `pf-upstream-sync` when convenient
```

This means anyone using your plugin in a session sees the drift warning, and the model can proactively suggest syncing if a relevant skill is triggered.

### Scheduled background agent

Use `/schedule` to set up a weekly remote agent that:

1. Runs `pf-upstream-status`
2. If any item is behind, opens an issue or posts to a Slack channel with the drift report
3. Optionally auto-syncs clean (non-modified) items and opens a PR with the diff

This catches upstream changes within a week without requiring a human to remember to check.

## License handling

Most plugins on the official marketplace are Apache 2.0. Soft-forking Apache-licensed content requires:

1. **Preserve the LICENSE file.** Copy the upstream's `LICENSE` into `.upstream/LICENSE-<source-name>`. Don't delete it.
2. **State changes.** The `notes` field on each `local_modified: true` item satisfies this — describe what you changed.
3. **Don't imply endorsement.** Don't name your plugin `anthropic-plugin-dev-extended` or use Anthropic / Claude Code trademarks in a way that suggests an official relationship.

That's it. Apache 2.0 doesn't restrict redistribution, charge fees, or require copyleft. Most other permissive licenses (MIT, BSD) have similar attribution requirements and are equally easy to comply with.

For non-permissive licenses (GPL, AGPL), check whether the upstream's terms allow vendoring at all and whether they impose obligations on your plugin. If in doubt, depend rather than vendor.

## Hybrid: soft-fork *and* depend

Nothing prevents combining both within one plugin. A reasonable hybrid:

- Soft-fork the skills you want to edit and absorb into your namespace
- Depend on plugins that ship runtime infrastructure you can't replicate (an MCP server, an LSP server, a complex hook setup)

The PROVENANCE table can include a fourth origin value, `dependency`, for those:

| Component | Type | Origin |
|---|---|---|
| `code-formatter` | mcp | dependency: `formatter@my-marketplace` |

Dependencies don't need an `.upstream/` entry — `dependencies` in `plugin.json` already records the relationship and the version pin.

## Summary

Soft-fork + upstream tracking is the right pattern when:

- You want one plugin, one namespace, one install for the user
- You'd rewrite upstream anyway, but it's a useful baseline
- You're willing to invest a one-time afternoon writing three small bin scripts and a SessionStart hook to keep yourself honest about drift

The cost is low — a few hundred lines of bash/jq tooling and a `manifest.json`. The benefit is high — you get the entire content base of any plugin you want, on your own schedule, in your own namespace, with the provenance trail to know what's borrowed and what's yours.

## See also

- **[Plugin Dependencies](./07_dependencies.md)** — the alternative composition primitive (depend instead of vendor)
- **[Ecosystem Mental Model](./01_ecosystem-mental-model.md)** — depend vs hand-author vs soft-fork decision matrix
- **[Marketplaces](../04_marketplaces.md)** — when soft-forking, you may want to host your plugin in your own marketplace rather than submitting upstream
- **[Reference](../07_reference.md)** — `${CLAUDE_PLUGIN_DATA}` (where to cache upstream snapshots), `/schedule` (for the weekly check)
