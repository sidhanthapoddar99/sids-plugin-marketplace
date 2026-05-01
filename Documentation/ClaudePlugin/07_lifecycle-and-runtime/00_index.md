# Lifecycle and runtime

The runtime side of plugins. How a plugin gets from "marketplace add" to "skills loaded into a session", what `/reload-plugins` does and doesn't pick up, when sessions need a full restart, and how multiple plugins compose without stepping on each other.

For *where* the files live see [`../03_storage-and-scope/`](../03_storage-and-scope/00_index.md).

## Sub-pages

| File | Topic |
|---|---|
| [`01_install-flow.md`](./01_install-flow.md) | `/plugin install` from marketplace ref to active boolean |
| [`02_activation-and-loading.md`](./02_activation-and-loading.md) | What loads when the plugin activates, in what order |
| [`03_hot-swap-matrix.md`](./03_hot-swap-matrix.md) | `/reload-plugins` per component type — what's hot-swappable, what isn't |
| [`04_updates.md`](./04_updates.md) | `/plugin update`, sibling-version drops, auto-update behaviour |
| [`05_garbage-collection.md`](./05_garbage-collection.md) | Orphan-marking, the 7-day window, `claude plugin prune` |
| [`06_schema-validation.md`](./06_schema-validation.md) | When `plugin.json` is validated, what fails, what's silently ignored |
| [`07_multi-plugin-merging.md`](./07_multi-plugin-merging.md) | `.mcp.json` / hook collisions across multiple enabled plugins |

## Related chapters

- [`../03_storage-and-scope/`](../03_storage-and-scope/00_index.md) — cache layout, data dir, scope union
- [`../11_testing-and-iteration/`](../11_testing-and-iteration/00_index.md) — `--plugin-dir` for skipping the install dance during dev
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — the inverse — uninstall mechanics and cache wipes
