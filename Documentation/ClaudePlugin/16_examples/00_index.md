# Examples

Worked, runnable examples illustrating the patterns described in the rest of the reference. Every example below is a complete plugin or marketplace you can copy, adapt, and load with `claude --plugin-dir <path>` or by adding the marketplace.

The companion plugin at `plugins/ai-toolkit-dev/` in this same repository is itself a worked example consumers can study — it ships three skills, soft-forks content from `claude-plugins-official`, and lives inside a self-hosted marketplace. Read its `README.md` and `.upstream/manifest.json` for a real-world reference implementation.

## Examples

| File | What it shows |
|---|---|
| [`01_minimal-plugin.md`](./01_minimal-plugin.md) | The smallest valid plugin — a directory with `.claude-plugin/plugin.json` containing only `name` and `description`. Auto-discovery picks up everything else |
| [`02_dogfood-marketplace.md`](./02_dogfood-marketplace.md) | A self-hosted marketplace where plugins live in the same repo as the marketplace manifest. `metadata.pluginRoot: "./plugins"` and `source: "./plugins/<name>"` |
| [`03_catalogue-marketplace.md`](./03_catalogue-marketplace.md) | A marketplace that *lists* third-party plugins it doesn't host. Every entry is an object source pointing at a different external repo |
| [`04_soft-fork-plugin.md`](./04_soft-fork-plugin.md) | A worked soft-fork plugin with `.upstream/manifest.json`, the README PROVENANCE table, and the per-plugin drift-check script that lives at the marketplace root |

## How to use these

Each example is self-contained — the file tree shown is everything you need. Copy the layout into a scratch directory, edit the names, and load it:

```bash
claude --plugin-dir /tmp/my-scratch-plugin
```

For marketplaces, add as a local marketplace:

```bash
claude /plugin marketplace add /tmp/my-marketplace
```

Then install:

```bash
claude /plugin install <plugin>@<marketplace>
```

## See also

- [`../05_plugin-anatomy/00_index.md`](../05_plugin-anatomy/00_index.md) — the manifest and folder shape these examples instantiate
- [`../04_marketplaces/00_index.md`](../04_marketplaces/00_index.md) — marketplace anatomy and source types
- [`../08_composition-patterns/00_index.md`](../08_composition-patterns/00_index.md) — hand-author / depend / soft-fork
- [`../11_testing-and-iteration/00_index.md`](../11_testing-and-iteration/00_index.md) — the `--plugin-dir` flag and the dev loop
