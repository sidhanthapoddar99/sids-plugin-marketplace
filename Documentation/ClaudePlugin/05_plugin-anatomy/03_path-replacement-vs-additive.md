# Path replacement vs additive semantics

When you set a component path field in `plugin.json`, the path either **replaces** the default scan or **supplements** it. The semantics differ by field, and the difference is silent — there is no warning if you assume the wrong one.

## The two rules

**Replacement** — the manifest field overrides the default scan path entirely. To keep the default *and* add more, you must list both.

**Additive** — the manifest field's paths are scanned *in addition to* the default. The default is always scanned regardless of what you set.

## Which is which

| Field | Default scanned | Semantics |
|---|---|---|
| `skills` | `skills/*/SKILL.md` | replacement |
| `commands` | `commands/*.md` | replacement |
| `agents` | `agents/*.md` | replacement |
| `outputStyles` | `outputStyles/*.md` | replacement |
| `themes` | `themes/*.json` | replacement |
| `monitors` | `monitors/monitors.json` | replacement |
| `hooks` | `hooks/hooks.json` | additive |
| `mcpServers` | `.mcp.json` | additive |
| `lspServers` | `.lsp.json` | additive |

The pattern is roughly: **content fields the model invokes** (skills, commands, agents, output styles, themes, monitors) are replacement; **runtime infrastructure that bolts on side-by-side** (hooks, MCP servers, LSP servers) is additive.

## Replacement: how to keep the default

Setting `"skills": "./extras/"` only scans `extras/`. The default `skills/` folder is ignored. To scan both, list both:

```json
{ "skills": ["./skills/", "./extras/"] }
```

This applies symmetrically across all replacement fields:

```json
{
  "commands": ["./commands/", "./vendor-commands/"],
  "agents": "./agents/",                              // identical to default; harmless
  "outputStyles": ["./outputStyles/", "./styles/"],
  "themes": ["./themes/", "./extras/themes/"],
  "monitors": ["./monitors/monitors.json", "./extras/monitors.json"]
}
```

## Additive: paths supplement the default

For hooks, MCP servers, and LSP servers, listing a custom path does not turn off the default scan:

```json
{
  "mcpServers": "./extras/mcp.json"
}
```

This loads both `.mcp.json` (the default) *and* `extras/mcp.json`. If your intent was "use `extras/mcp.json` instead", you have to delete `.mcp.json` from the plugin folder — there is no manifest-level way to suppress the default.

The same applies to `hooks` and `lspServers`.

## Inline config as an alternative

For the additive fields, you can avoid the file entirely by inlining the config object in the manifest:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-server.js"]
    }
  }
}
```

When the field is an object, the default file (`.mcp.json`) is *still scanned* — additive semantics apply to objects, paths, and arrays equally.

## Common mistakes

- **Assuming `"skills": "./extras/"` keeps the default `skills/` scan.** It doesn't — default replacement means the manifest's value is the *complete* list. Add `./skills/` explicitly if you want both.
- **Worrying that an additive default file will break your setup.** It won't — if `.mcp.json` doesn't exist, the additive scan finds nothing, no error.
- **Putting two MCP servers under the same name in default + custom configs.** Names must be unique across the merged set; collision = load-time error.
- **Mixing inline config with a same-named entry in the default file.** First definition wins; the second is silently ignored. Use one or the other.

## Why the asymmetry

The replacement-vs-additive split tracks the cost of unintended discovery. A spurious skill or theme that auto-loads is a UX regression — the user sees something in `/theme` they didn't expect. A spurious hook or MCP server doesn't load anything visible *unless* the file is well-formed and matches a real entry, so the failure mode is much milder.

It's also a performance concession: replacement-field scans are cheap (one directory walk), but the default `.mcp.json` / `hooks/hooks.json` files are commonly overridden by inline manifest values, and the additive default catches the case where an author forgets to set the field after migrating to inline.

## See also

- [`01_directory-layout.md`](./01_directory-layout.md) — the conventional folders being scanned
- [`02_manifest-fields.md`](./02_manifest-fields.md) — full manifest reference
- [`../06_capabilities/00_index.md`](../06_capabilities/00_index.md) — what each capability does
