# Soft-fork + upstream tracking

A third pattern between depending and hand-authoring. You **copy upstream content into your plugin** (so it lives in your namespace, ships in your install, and you can edit it freely), but you keep a *provenance manifest* that records where each piece came from, when you last synced it, and what local edits you've made. Tooling tells you when upstream has changed, and you decide whether to merge.

This is how OS distributions vendor third-party libraries, how Go projects use vendored modules, and how `chromium` keeps its v8 copy honest. Same idea applied to plugins.

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
│   ├── plugin-validator.md          ← soft-imported, extended (illustrative — your soft-fork picks whichever upstream agents you want)
│   └── release-manager.md           ← in-house original
│
├── bin/                             ← OPTIONAL — see "the three small bin scripts"
│   ├── pf-upstream-status
│   ├── pf-upstream-sync
│   └── pf-upstream-log
│
└── hooks/hooks.json                 ← optional SessionStart hook for staleness checks
```

Two key conventions:

- **`.upstream/`** holds provenance metadata and license attribution for vendored content. Not loaded by the plugin runtime; it's purely authoring discipline.
- **`README.md`** at the plugin root surfaces the PROVENANCE table (see below) so consumers — and you, six months from now — can see at a glance which skills are yours and which were borrowed.

## The provenance manifest

`.upstream/manifest.json` records one entry per vendored item. Both the file path *inside your plugin* and the *upstream path it came from* are tracked, so syncing tools can correlate them.

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
      "notes": "Added prompt-based hook section, $CLAUDE_ENV_FILE, hot-swap limitation"
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

### Per-item fields

| Field | Purpose |
|---|---|
| `source` | Key into `sources` — which upstream this came from |
| `upstream_path` | Path relative to upstream repo root |
| `last_synced_sha` | Upstream commit SHA at last sync (12-char prefix is enough) |
| `last_synced_date` | When you last pulled from upstream |
| `local_modified` | `true` if you've edited the file since the last sync. Auto-sync skips these |
| `local_modified_date` | When local edits were made (for audit) |
| `notes` | What you changed and why. Required when `local_modified: true` for Apache 2.0 attribution and your own future understanding |

Items not listed in this manifest are assumed to be **in-house originals** with no upstream relationship.

### Real-world manifest variant

The `ai-toolkit-dev` plugin in this marketplace uses a slightly different shape — the same idea but flatter, with `upstream` (singular source) instead of `sources` (multiple), and an `entries[]` array instead of an `items{}` map:

```json
{
  "schema_version": "1.0",
  "upstream": {
    "repo": "anthropics/claude-plugins-official",
    "ref": "main",
    "vendored_commit": "0742692199b49af5c6c33cd68ee674fb2e679d50",
    "vendored_at": "2026-05-01",
    "license": "Apache-2.0",
    "license_file": ".upstream/LICENSE-plugin-dev"
  },
  "entries": [
    {
      "local": "skills/plugin-dev/references/topics/plugin-structure/",
      "upstream": "plugins/plugin-dev/skills/plugin-structure/",
      "sha": "2438937",
      "vendored_at": "2026-05-01",
      "modifications": []
    }
  ],
  "dropped": [
    {
      "upstream": "plugins/plugin-dev/skills/skill-development/",
      "reason": "Superseded by skills/skill-creator/ (vendored separately)"
    }
  ]
}
```

The `dropped[]` field is a useful addition for tracking upstream items you deliberately did *not* vendor, so a future sync doesn't accidentally re-import them.

Both shapes work. Pick whichever reads cleaner for your plugin's tooling.

## The PROVENANCE table (in your README)

This is the human-readable companion to `manifest.json`. Put it at the top of `README.md`:

```markdown
## Plugin contents

| Component | Type | Origin | Local edited | Upstream sync | Drift | License |
|---|---|---|---|---|---|---|
| `hook-development` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `mcp-integration` | skill | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`2438937`) | up-to-date | Apache-2.0 |
| `marketplace-authoring` | skill | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `plugin-validator` | agent | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`82d0412`) | up-to-date | Apache-2.0 |
| `release-manager` | agent | **in-house** | 2026-04-30 | — | n/a | <your license> |
| `/create-plugin` | command | soft-import: plugin-dev | 2026-04-30 | 2026-04-30 (`6b70f99`) | up-to-date | Apache-2.0 |
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

Auto-generate this table from `manifest.json` to keep it accurate.

## Tooling pattern: three small bin scripts

Pick a 2-3 character namespace prefix (e.g., `pf-` for "plugin-forge"). The three scripts:

### `pf-upstream-status`

For each item in `manifest.json`:

1. Hit the GitHub API for the latest commit on `upstream_path` at the source's tracked ref
2. Compare to `last_synced_sha`
3. Print a status line per item

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

> [!note]
> The bin scripts are **optional** — they're convenience tooling for plugin authors. A plugin without them still works for consumers; they just can't run drift checks themselves. If your plugin lives in a marketplace, an alternative is to put a single drift-check script at the **marketplace root** (e.g. `scripts/<plugin>-check-upstream`) instead of shipping bin scripts to consumers. See [`../16_examples/04_soft-fork-plugin.md`](../16_examples/04_soft-fork-plugin.md).

## Automating staleness checks

### SessionStart hook

A small script that runs `pf-upstream-status --json` and counts items not `up-to-date`. If any are behind, it injects a one-line system reminder for the model:

```
[plugin-forge] 3 vendored items are behind upstream — run `pf-upstream-sync` when convenient
```

Anyone using your plugin in a session sees the drift warning, and the model can proactively suggest syncing if a relevant skill is triggered.

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
- You're willing to invest a one-time afternoon writing the tooling and a SessionStart hook to keep yourself honest about drift

The cost is low — a few hundred lines of bash/jq tooling and a `manifest.json`. The benefit is high — you get the entire content base of any plugin you want, on your own schedule, in your own namespace, with the provenance trail to know what's borrowed and what's yours.

## See also

- [`02_depend.md`](./02_depend.md) — the alternative composition primitive
- [`01_hand-author.md`](./01_hand-author.md) — when there's no upstream worth borrowing from
- [`../03_storage-and-scope/02_data-dir.md`](../03_storage-and-scope/02_data-dir.md) — `${CLAUDE_PLUGIN_DATA}` for caching upstream snapshots
- [`../16_examples/04_soft-fork-plugin.md`](../16_examples/04_soft-fork-plugin.md) — worked example referencing `plugins/ai-toolkit-dev/`
- [`../04_marketplaces/00_index.md`](../04_marketplaces/00_index.md) — when soft-forking, you may want your own marketplace
