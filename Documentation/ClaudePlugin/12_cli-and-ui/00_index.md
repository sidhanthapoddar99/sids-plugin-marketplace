# CLI and UI

Claude Code exposes plugin operations through three surfaces. Each does the same things, optimised for a different context: the interactive `/plugin` UI for discovery, the built-in slash commands for quick prompt-line operations, and the `claude plugin` CLI for scripts and CI.

## The three surfaces

| Surface | Best for | Example |
|---|---|---|
| `claude plugin <subcommand>` | Scripts, CI, automation, headless installs | `claude plugin install foo@my-mkt --scope project` |
| `/plugin` (and `/plugin marketplace …`) | Interactive prompt-line operations during a session | `/plugin install foo@my-mkt` |
| `/plugin` UI (the tabbed picker) | Browsing, discovering, managing many plugins | Tab through Discover / Installed / Marketplaces / Errors |

Operations are equivalent across surfaces. Pick by context:

- In a script or CI job → `claude plugin <subcommand>`
- Inside an active session, you know the plugin name → slash command
- Inside an active session, you're exploring or have many plugins to manage → `/plugin` UI

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_claude-plugin-cli.md` | Every `claude plugin` subcommand, flag, scope behaviour, examples |
| 02 | `02_built-in-slash-commands.md` | `/plugin`, `/plugin marketplace`, `/reload-plugins`, `/hooks`, `/mcp`, `/agents`, `/theme`, `/doctor` |
| 03 | `03_plugin-ui.md` | The tabbed UI — Discover, Installed, Marketplaces, Errors. Navigation, sort priority, per-tab actions |

## Related chapters

- [`../11_testing-and-iteration/`](../11_testing-and-iteration/00_index.md) — `--plugin-dir` and `claude -p` are CLI flags, not subcommands; covered there
- [`../15_reference/`](../15_reference/00_index.md) — env-var and settings-key cheat sheets that affect CLI / UI behaviour
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — uninstall semantics and cache wipe
