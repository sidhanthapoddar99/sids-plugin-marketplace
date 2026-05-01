# Mental Model

Three different observers — the model, the runtime, and the plugin author — see different things. This split is the single most important concept for understanding why plugins behave the way they do.

The chapter assumes you've read [01_overview.md](../01_overview.md) for the layered architecture summary.

## Why the split matters

Many design decisions only make sense once you know which layer you're talking to. Examples:

- A skill description must be excellent because it's the only thing the **model** sees until trigger time.
- A `bin/` wrapper script gets discovered by the **runtime** (PATH augmentation) but invoked by the **model** (via `Bash`).
- The plugin manifest matters to the **runtime** for loading and to the **author** for distribution — but is invisible to the model.
- A hook fires entirely in the runtime; the model has no idea the hook ran.

Author intuitions formed at one layer break at another layer. This chapter draws the boundaries explicitly.

## Sub-pages

| File | Topic |
|---|---|
| [01_what-the-model-sees.md](./01_what-the-model-sees.md) | Skills, slash commands, subagents, MCP tools, bin scripts on `$PATH` — and what hooks *don't* show |
| [02_what-the-runtime-sees.md](./02_what-the-runtime-sees.md) | The cache, scope union, hooks, PATH augmentation, schema validation, `/plugin` UI |
| [03_packaging-vs-capabilities.md](./03_packaging-vs-capabilities.md) | Plugin = packaging; capabilities = behaviour. Indistinguishability of hand-authored vs. plugin-shipped |
| [04_naming-and-namespacing.md](./04_naming-and-namespacing.md) | `<plugin>@<marketplace>`, `<plugin>:<skill>`, collision rules, bin/MCP name conflicts |

## See also

- [01_overview.md](../01_overview.md) — prerequisite read
- [Capabilities](../06_capabilities/00_index.md) — the unpacked behaviours covered here in detail
