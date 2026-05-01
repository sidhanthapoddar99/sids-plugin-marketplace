# Directory layout

Every plugin is a folder containing a manifest plus zero or more capability folders. The shape is conventional; only `.claude-plugin/plugin.json` is required, and even that can be omitted (Claude Code derives the name from the folder and auto-discovers components).

## Full conventional layout

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json           ← MANIFEST (the only structurally required file)
├── README.md                  ← shown in /plugin UI
├── LICENSE                    ← required for distribution
├── settings.json              ← optional plugin-shipped Claude Code defaults (see 05)
│
├── bin/                       ← AUTO-ADDED to $PATH at session start
│   └── <executable>           ← chmod +x; no extension on UNIX
│
├── commands/                  ← legacy slash commands (prefer skills/)
│   └── <name>.md              ← filename minus .md = /<name>
├── agents/                    ← subagent configs
│   └── <name>.md              ← filename = agent type
├── skills/                    ← per-skill folders
│   └── <skill-name>/
│       ├── SKILL.md           ← frontmatter + body, required exactly
│       ├── references/        ← progressive-disclosure files cited from SKILL.md
│       └── scripts/           ← bundled scripts (.mjs, .py, .sh)
│
├── hooks/                     ← runtime hooks
│   └── hooks.json             ← hook config
├── monitors/                  ← background watcher processes
│   └── monitors.json
├── themes/                    ← color theme JSON files
│   └── <name>.json
├── outputStyles/              ← response-formatting styles
│   └── <name>.md
├── channels/                  ← messaging-surface bindings (Telegram/Slack/Discord)
│   └── <name>.json
│
├── .mcp.json                  ← MCP server registrations
├── .lsp.json                  ← LSP server registrations
│
├── scripts/                   ← free-form, called by your other components
├── assets/                    ← free-form bundled data (templates, fixtures)
└── .upstream/                 ← optional, for soft-fork plugins (see 08)
```

Capability folders only need to exist if they contain something. A plugin shipping just one skill has only `skills/`; a plugin shipping just a hook has only `hooks/`.

## Folder reference

| Path | Auto-discovered? | Purpose |
|---|---|---|
| `.claude-plugin/plugin.json` | n/a (the manifest itself) | Required by convention; auto-discovery still works without it |
| `.claude-plugin/marketplace.json` | n/a | Present only if the entity is a *marketplace*, not just a plugin |
| `bin/` | yes | Each executable is added to `$PATH` while the plugin is enabled |
| `commands/*.md` | yes | One file per slash command. Legacy layout — prefer skills |
| `agents/*.md` | yes | One file per subagent |
| `skills/*/SKILL.md` | yes | One folder per skill, `SKILL.md` exactly (uppercase, required) |
| `hooks/hooks.json` | yes | Inline or referenced hook config |
| `monitors/monitors.json` | yes | Background watcher processes (Claude Code v2.1.105+) |
| `themes/*.json` | yes | Color themes that show up in `/theme` |
| `outputStyles/*.md` | yes | Response-formatting style files |
| `channels/*.json` | yes | Channel definitions bound to MCP servers |
| `.mcp.json` | yes | MCP server registrations |
| `.lsp.json` | yes | LSP server registrations |
| `scripts/` | no | Free-form. Called from your skills, hooks, bin scripts, etc. |
| `assets/` | no | Free-form bundled data (templates, fixtures, sample configs) |
| `.upstream/` | no | Provenance metadata for soft-forked content. See [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md) |

The default discovery paths can be replaced or supplemented per the rules in [`03_path-replacement-vs-additive.md`](./03_path-replacement-vs-additive.md).

## File naming rules

| Path | Convention |
|---|---|
| `.claude-plugin/plugin.json` | Exact name, lowercase |
| `commands/*.md` | Lowercase filename = command name |
| `agents/*.md` | Lowercase filename = agent name |
| `skills/<name>/SKILL.md` | `SKILL.md` is uppercase and required exactly |
| `hooks/hooks.json` | Lowercase, exact |
| `monitors/monitors.json` | Lowercase, exact |
| `bin/*` | OS-conventional; no extension on UNIX |
| `.mcp.json`, `.lsp.json` | Lowercase, exact, dot-prefixed |

Plugin and component names must match `[a-z][a-z0-9-]*` (kebab-case ASCII). Plugin names are 3–64 characters with no leading/trailing/consecutive dashes.

## `${CLAUDE_PLUGIN_ROOT}` and where it expands

`${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installed cache directory. Use it any time a file inside the plugin needs to reference another file inside the plugin.

| Substitutes inline in | Notes |
|---|---|
| `.mcp.json`, `.lsp.json` server configs | Including `command`, `args`, `cwd`, `env` |
| Hook commands (`hooks/hooks.json`) | Substituted before exec |
| Monitor commands (`monitors/monitors.json`) | Substituted before exec |
| `allowed-tools` frontmatter on commands | Recognised in pattern matching |
| Inline command bodies (front-of-prompt) | Substitution at command-fire time |
| Skill / agent body content | Substitutes for non-sensitive `${user_config.KEY}` only — `${CLAUDE_PLUGIN_ROOT}` itself does **not** expand here, since skills run in the model's read-only context, not a shell |

The companion variable `${CLAUDE_PLUGIN_DATA}` survives plugin updates and is the right place for caches, dependency installs, and learned data. See [`../03_storage-and-scope/02_data-dir.md`](../03_storage-and-scope/02_data-dir.md).

> [!note]
> Inside `SKILL.md` body content the model can't expand `${CLAUDE_PLUGIN_ROOT}` itself. To reference bundled assets from within a skill, prefer absolute paths recorded in env vars exported by a SessionStart hook, or have the skill instruct a `Bash` call that reads `$CLAUDE_PLUGIN_ROOT` directly.

## Path-traversal limit

Plugins **cannot reference files outside their own root** after install. Paths like `../shared-utils` won't resolve, because external files aren't copied into the cache. Bundle everything you need inside the plugin folder.

This is enforced at install time — the marketplace's source-fetcher copies the plugin folder verbatim and nothing else. There's no symlink-honoring, no "include" directive, no shared-library mechanism between plugins. The composition primitives are dependencies and soft-forking, both covered in [`../08_composition-patterns/00_index.md`](../08_composition-patterns/00_index.md).

## When the manifest can be omitted entirely

If you don't ship a `.claude-plugin/plugin.json`:

- The plugin name is derived from the folder name
- Default-discovery still scans `commands/`, `agents/`, `skills/`, `hooks/`, `bin/`, `.mcp.json`, `.lsp.json`, `themes/`, `monitors/`, `outputStyles/`
- Identity metadata (description, version, author, license) is unset
- You cannot declare `userConfig`, `dependencies`, `channels`, or any modern field

Useful for the very-first iteration of a plugin you're loading via `claude --plugin-dir <path>`. For anything published to a marketplace, ship the manifest — at minimum `name` and `description`.

## See also

- [`02_manifest-fields.md`](./02_manifest-fields.md) — every field the manifest accepts
- [`03_path-replacement-vs-additive.md`](./03_path-replacement-vs-additive.md) — overriding default discovery paths
- [`../03_storage-and-scope/01_cache-layout.md`](../03_storage-and-scope/01_cache-layout.md) — where the plugin folder lands once installed
- [`../06_capabilities/00_index.md`](../06_capabilities/00_index.md) — what goes inside each capability folder
- [`../16_examples/01_minimal-plugin.md`](../16_examples/01_minimal-plugin.md) — worked example of the smallest valid plugin
