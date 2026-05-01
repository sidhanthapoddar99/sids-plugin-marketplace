# Soft-fork plugin

A worked example of a plugin that vendors content from `claude-plugins-official` with a provenance manifest. The live reference implementation is `plugins/ai-toolkit-dev/` in this same repository — read its `README.md`, `.upstream/manifest.json`, and `plugin.json` for the real version.

This page walks through the same shape with the supporting tooling (a marketplace-level drift-check script) wired in.

## File tree

```
sids-plugin-marketplace/
├── .claude-plugin/
│   └── marketplace.json
├── scripts/
│   └── ai-toolkit-dev-check-upstream      ← drift-check script (marketplace-level)
└── plugins/
    └── ai-toolkit-dev/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── README.md                       ← includes PROVENANCE table
        ├── LICENSE                         ← your plugin's license
        │
        ├── .upstream/                      ← provenance & licensing
        │   ├── manifest.json               ← machine-readable provenance
        │   └── LICENSE-plugin-dev          ← upstream Apache-2.0 LICENSE preserved
        │
        └── skills/
            ├── plugin-dev/
            │   ├── SKILL.md                ← in-house entry point
            │   └── references/
            │       └── topics/             ← vendored from upstream
            │           ├── plugin-structure/
            │           ├── agent-development/
            │           ├── command-development/
            │           ├── hook-development/
            │           ├── mcp-integration/
            │           └── plugin-settings/
            ├── skill-creator/              ← vendored from upstream
            └── marketplace/                ← in-house
```

The plugin lives under a dogfood marketplace (see [`02_dogfood-marketplace.md`](./02_dogfood-marketplace.md)). The drift-check script lives at the **marketplace root**, not inside the plugin — see "Drift-check script lives at the marketplace level" below.

## `.claude-plugin/plugin.json`

The plugin manifest uses an explicit `skills` array (replacement semantics — see [`../05_plugin-anatomy/03_path-replacement-vs-additive.md`](../05_plugin-anatomy/03_path-replacement-vs-additive.md)) to list each skill folder it ships:

```json
{
  "name": "ai-toolkit-dev",
  "description": "Toolkit for authoring Claude Code plugins, marketplaces, and skills",
  "author": {
    "name": "Sid",
    "email": "developer@neuralabs.org"
  },
  "skills": [
    "./skills/marketplace/",
    "./skills/plugin-dev/",
    "./skills/skill-creator/"
  ]
}
```

The manifest contains nothing soft-fork-specific. Soft-forking is a content-organisation pattern, not a Claude Code feature — the runtime never reads `.upstream/`.

## `.upstream/manifest.json`

The provenance manifest. Records one entry per vendored item:

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
    },
    {
      "local": "skills/plugin-dev/references/topics/agent-development/",
      "upstream": "plugins/plugin-dev/skills/agent-development/",
      "sha": "ce721c1",
      "vendored_at": "2026-05-01",
      "modifications": []
    },
    {
      "local": "skills/skill-creator/",
      "upstream": "plugins/skill-creator/skills/skill-creator/",
      "sha": "2a40fd2",
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

Per-entry fields:

| Field | Purpose |
|---|---|
| `local` | Path relative to the plugin root |
| `upstream` | Path relative to the upstream repo root |
| `sha` | Upstream commit SHA at last sync (7-char prefix is enough) |
| `vendored_at` | When you last pulled from upstream |
| `modifications` | Array of strings describing local edits since the last sync. Empty `[]` means no local modifications |

The `dropped` array is a useful addition — it records upstream items you deliberately did *not* vendor, so a future sync doesn't accidentally re-import them.

For the alternative (per-source) manifest shape, see [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md).

## README PROVENANCE table

The README.md leads with a table mapping every component to its origin:

```markdown
## Plugin contents

| Component | Type | Origin | Vendored | Drift | License |
|---|---|---|---|---|---|
| `marketplace` | skill | **in-house** | — | n/a | <your license> |
| `plugin-dev` | skill | mixed (in-house entry; vendored topic refs) | 2026-05-01 | check via script | mixed |
| `plugin-dev/references/topics/plugin-structure/` | reference | soft-import: plugin-dev | `2438937` | check via script | Apache-2.0 |
| `plugin-dev/references/topics/agent-development/` | reference | soft-import: plugin-dev | `ce721c1` | check via script | Apache-2.0 |
| `plugin-dev/references/topics/command-development/` | reference | soft-import: plugin-dev | `6b70f99` | check via script | Apache-2.0 |
| `plugin-dev/references/topics/hook-development/` | reference | soft-import: plugin-dev | `2438937` | check via script | Apache-2.0 |
| `plugin-dev/references/topics/mcp-integration/` | reference | soft-import: plugin-dev | `2438937` | check via script | Apache-2.0 |
| `plugin-dev/references/topics/plugin-settings/` | reference | soft-import: plugin-dev | `2438937` | check via script | Apache-2.0 |
| `skill-creator` | skill | soft-import: skill-creator | `2a40fd2` | check via script | Apache-2.0 |
```

Reading this table tells the consumer (and you, six months from now) what came from where, when it was vendored, and what license applies. Generate the table from `manifest.json` so it stays accurate.

## Drift-check script lives at the marketplace level

The standard soft-fork pattern (see [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md)) describes shipping `bin/` scripts inside the plugin. For a single-plugin soft-fork in a dogfood marketplace, an alternative is to put a single drift-check script at the **marketplace root** instead:

```
sids-plugin-marketplace/
└── scripts/
    └── ai-toolkit-dev-check-upstream
```

Why: shipping bin scripts in the plugin clutters every consumer's `$PATH`, but the drift check is only useful to *plugin authors*, not consumers. Keeping it at the marketplace level means the plugin install stays clean and the script lives next to the marketplace tooling.

The script itself, abbreviated:

```bash
#!/usr/bin/env bash
# ai-toolkit-dev-check-upstream — report drift between vendored soft-fork
# content in plugins/ai-toolkit-dev and the upstream sources.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLUGIN="ai-toolkit-dev"
manifest="plugins/$PLUGIN/.upstream/manifest.json"

if [[ ! -f "$manifest" ]]; then
  echo "No manifest at $manifest. Soft-fork hasn't been performed yet."
  exit 0
fi

printf "%-60s %-12s %-12s %s\n" "TRACKED PATH" "VENDORED" "UPSTREAM" "STATUS"

repo=$(jq -r '.upstream.repo' "$manifest")
ref=$(jq -r '.upstream.ref // "main"' "$manifest")
count=$(jq '.entries | length' "$manifest")

for i in $(seq 0 $((count - 1))); do
  local_path=$(jq -r ".entries[$i].local" "$manifest")
  upstream_path=$(jq -r ".entries[$i].upstream" "$manifest")
  vendored_sha=$(jq -r ".entries[$i].sha" "$manifest")

  upstream_sha=$(gh api "repos/$repo/commits?path=$upstream_path&sha=$ref&per_page=1" 2>/dev/null \
                  | jq -r '.[0].sha[0:7]' || echo "ERR")

  if [[ "$upstream_sha" == "${vendored_sha:0:7}" ]]; then
    status="up to date"
  elif [[ "$upstream_sha" == "ERR" ]]; then
    status="lookup failed"
  else
    status="DRIFT"
  fi

  printf "%-60s %-12s %-12s %s\n" "$local_path" "${vendored_sha:0:7}" "$upstream_sha" "$status"
done
```

(The full real script lives at `scripts/ai-toolkit-dev-check-upstream` in this repo. Requires `gh` and `jq`.)

Output:

```
TRACKED PATH                                                 VENDORED     UPSTREAM     STATUS
skills/plugin-dev/references/topics/plugin-structure/        2438937      2438937      up to date
skills/plugin-dev/references/topics/hook-development/        2438937      a91c45f      DRIFT
skills/skill-creator/                                        2a40fd2      2a40fd2      up to date
```

## Per-plugin scoping

Drift checks are **per-plugin scoped**. If a second plugin grows soft-fork tracking later, give it its own `scripts/<plugin>-check-upstream`. Don't retrofit one global script — each plugin's manifest may evolve independently and conflating them adds coupling.

The `CLAUDE.md` at the marketplace root reminds agents and authors of this convention:

```
Drift checks are per-plugin scoped. If another plugin grows soft-fork
tracking later, it gets its own scripts/<plugin>-check-upstream;
do not retrofit one global script.
```

## License handling

Apache 2.0 vendoring requires:

1. **Preserve the LICENSE file.** `.upstream/LICENSE-plugin-dev` is the upstream's `LICENSE` copied verbatim.
2. **State changes.** The `modifications[]` array on each entry satisfies this — describe what you changed.
3. **Don't imply endorsement.** Don't name your plugin `anthropic-plugin-dev-extended` or use Anthropic / Claude Code trademarks suggestively.

That's it. See [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md) for non-Apache cases.

## Sync workflow

When the drift-check script reports DRIFT:

1. Run it (`./scripts/ai-toolkit-dev-check-upstream`) to see which items are behind.
2. For each behind item, fetch the upstream version and compare to the local copy.
3. If `modifications[]` is empty: overwrite the local file, update `sha` and `vendored_at` in the manifest.
4. If `modifications[]` is non-empty: read the upstream changes, decide whether to merge them with your local edits, edit the local file, update `sha` / `vendored_at` / `modifications[]` in the manifest.
5. Regenerate the README PROVENANCE table from the manifest.
6. Commit with a message like `sync ai-toolkit-dev/skill-creator from upstream a91c45f`.

Steps 1–2 can be automated with the script. Steps 3–6 are manual review-and-merge.

## See also

- The live implementation: `plugins/ai-toolkit-dev/` and `scripts/ai-toolkit-dev-check-upstream` in this repo
- [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md) — the soft-fork pattern in full
- [`02_dogfood-marketplace.md`](./02_dogfood-marketplace.md) — the marketplace shape this plugin lives in
- [`../05_plugin-anatomy/02_manifest-fields.md`](../05_plugin-anatomy/02_manifest-fields.md) — explicit `skills` field with replacement semantics
- The marketplace's `CLAUDE.md` — agent guidance for the soft-fork pattern in this specific repo
