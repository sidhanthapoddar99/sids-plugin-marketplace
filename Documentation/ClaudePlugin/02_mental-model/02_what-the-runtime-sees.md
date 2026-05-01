# What the Runtime Sees

The runtime — Claude Code itself — knows about plugins as units. It loads them, fires their hooks, augments `$PATH`, validates schemas, and surfaces them in the `/plugin` UI. This is the layer the model never sees.

## Plugins as units

To the runtime, each plugin is a directory under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, identified by the install identifier `<plugin>@<marketplace>`. The runtime tracks:

- Which version is currently active
- Which scopes have it enabled (Managed, User, Project, Local)
- Whether its manifest validates
- Which capabilities it ships
- Which hooks it has registered
- Which MCP servers, LSP servers, and monitors it spawns
- Which `bin/` directory needs to be on `$PATH`

The unit identity flows through the whole lifecycle: install, enable/disable, update, uninstall, GC.

## Cache layout

```
~/.claude/plugins/
├── cache/
│   └── <marketplace-name>/
│       └── <plugin-name>/
│           ├── 0.1.0/                  ← prior version (orphaned, GC'd after 7 days)
│           └── 0.2.0/                  ← current version
│               ├── .claude-plugin/plugin.json
│               ├── bin/
│               ├── skills/
│               ├── commands/
│               └── …
└── data/
    └── <plugin-id>/                    ← persistent data, survives plugin updates
```

Files live **once**, at user level, regardless of which scope enabled them. There is no per-project plugin cache.

Multiple versions can coexist — `/plugin update` lays down a new version folder beside the previous one, then switches the active version. The previous version is marked orphaned and removed 7 days later. The grace window lets concurrent sessions that already loaded the old version keep running.

## Scope union

At session start, the runtime reads `enabledPlugins` from every applicable scope and computes the **union**. Each enabled plugin loads **once**, even if multiple scopes enable it.

| Scope | settings.json | Visibility |
|---|---|---|
| **Managed** | Set by admin | Locked, can't be overridden |
| **User** | `~/.claude/settings.json` | All projects on this machine |
| **Project** | `<repo>/.claude/settings.json` | This project, all teammates (committed) |
| **Local** | `<repo>/.claude/settings.local.json` | This project, just you (gitignored) |

Precedence (more specific wins): Managed > Local > Project > User. Empirically verified: enabling the same plugin at user and project scope simultaneously results in exactly one cache folder, one set of skills loaded, one entry in `/reload-plugins` output.

## PATH augmentation

Every enabled plugin's `bin/` folder is prepended to the bash `$PATH` at session start. The model can then call any executable in any plugin's `bin/` via the `Bash` tool — same as a system command.

Name collisions on `$PATH` resolve in PATH order (first one wins). See [04_naming-and-namespacing.md](./04_naming-and-namespacing.md) for the conflict semantics.

## Hooks

Hooks are runtime-only. The runtime parses each plugin's hook config (either `hooks/` folder or inline `hooks` field in `plugin.json`) at session start and wires matchers to lifecycle events:

- `PreToolUse` / `PostToolUse`
- `UserPromptSubmit`
- `Stop` / `SubagentStop`
- `SessionStart` / `SessionEnd`
- `PreCompact`
- `Notification`

Each fires the matching shell command(s). Hooks can block tool calls (exit 1), inject context (stdout becomes a system reminder), or run arbitrary side effects.

Hooks **load at session start**. Editing hook config requires a full session restart — `/reload-plugins` does NOT pick up hook changes. Other capabilities (skills, commands, agents, MCP, LSP) *are* reloaded by `/reload-plugins`.

## Schema validation

The runtime validates `plugin.json` and `marketplace.json` against the bundled JSON schemas. Validation errors:

- Surface in the `/plugin` Errors tab
- Show up in `/doctor`
- Are listed in `claude plugin list --json` under the `errors` field

Unknown keys in plugin-shipped `settings.json` (the in-plugin defaults file, not the user's) are silently ignored — only `agent` and `subagentStatusLine` are recognised currently.

## The `/plugin` UI — four tabs

The interactive plugin manager has four tabs you cycle through with **Tab** / **Shift+Tab**:

| Tab | What it shows |
|---|---|
| **Discover** | Browse plugins from all your marketplaces; categories from each plugin entry's `category` |
| **Installed** | View/manage installed plugins. Press `f` to favorite, type to filter, Enter for detail view. Sort: errors → favorites → enabled → disabled |
| **Marketplaces** | Add/remove/update marketplaces |
| **Errors** | Load errors and unresolved dependencies |

The `/plugin` UI is one of the runtime's primary surfaces — it's where users see plugins-as-units. (The model never sees the UI; the user does.)

## What the runtime fetches and when

| Action | What happens |
|---|---|
| `/plugin install` | Fetch from marketplace → copy to cache → write `enabledPlugins` boolean → reload |
| `/plugin update` | Re-fetch from marketplace → drop new version directory → switch active version → mark old as orphaned |
| `/plugin uninstall` | Remove `enabledPlugins` boolean → typically clear cache folder. `--keep-data` preserves `${CLAUDE_PLUGIN_DATA}` |
| `/plugin enable` / `disable` | Flip the `enabledPlugins` boolean — files stay in cache |
| `/reload-plugins` | Re-read installed plugins from cache without re-downloading. Does NOT pick up hook changes |
| Session start | Run scope union → load each enabled plugin once → register hooks → augment `$PATH` → start MCP/LSP/monitors |

## See also

- [01_what-the-model-sees.md](./01_what-the-model-sees.md) — the other side of the split
- [Storage and Scope](../03_storage-and-scope/00_index.md) — cache, data dir, scope union in depth
- [Lifecycle and Runtime](../07_lifecycle-and-runtime/00_index.md) — install/activation/update/GC mechanics
- [CLI and UI](../12_cli-and-ui/00_index.md) — the `/plugin` UI in detail
