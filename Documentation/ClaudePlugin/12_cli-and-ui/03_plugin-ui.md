# `/plugin` UI

The tabbed interactive plugin manager. Opened by `/plugin` and stays open until dismissed.

## The four tabs

Cycle with **Tab** (next) and **Shift+Tab** (previous):

| Tab | Shows | Primary action |
|---|---|---|
| **Discover** | Plugins available across all installed marketplaces | Install |
| **Installed** | Plugins currently registered in `enabledPlugins` at any scope | Enable / disable / favorite / uninstall |
| **Marketplaces** | Marketplaces you've added | Add / remove / update / configure auto-update |
| **Errors** | Load errors and unresolved dependencies | Inspect error message; jump to the plugin |

There is **no Browse tab** and **no Settings tab** — those names are common assumptions but not real. The four above are exhaustive.

## Universal navigation

| Key | Action |
|---|---|
| Tab / Shift+Tab | Cycle tabs |
| Up / Down | Move within the current list |
| Enter | Open detail view for the highlighted item |
| Type | Filter the current list (substring match against name + description) |
| Esc | Close the picker |

## Discover tab

Lists every plugin every installed marketplace catalogues. For each entry: name, marketplace, version, one-line description.

| Key | Action |
|---|---|
| Enter | Open the plugin's detail view (full description, README rendering, install command) |
| `i` | Install the highlighted plugin |
| Type | Filter by name / description |

Filtering combines across name + description, so `lint` matches "ESLint plugin" and "linting helper" alike.

Installation prompts for `userConfig` values (if declared) before completing. After install, the plugin appears in the Installed tab.

## Installed tab

Lists plugins enabled at any scope. The list **sort priority** matters:

| Order | Group |
|---|---|
| 1st (top) | Plugins with errors — highlighted |
| 2nd | Favorites — marked with a star |
| 3rd | Normal enabled plugins |
| Bottom | Disabled plugins — collapsed by default |

Per-plugin actions:

| Key | Action |
|---|---|
| Enter | Open detail view |
| `f` | Toggle favorite |
| `d` | Disable (plugin stays installed; boolean flips to false) |
| `e` | Enable (boolean flips to true) |
| `u` | Uninstall |
| Type | Filter the list |

Errors appearing first means broken plugins are unmissable. Favorites surface things you reach for daily without searching.

## Marketplaces tab

Lists every marketplace registered at any scope. For each: name, source URL/path, ref pin (if any), per-marketplace auto-update setting.

| Key | Action |
|---|---|
| Enter | Open marketplace detail (plugins it lists, last update time) |
| `a` | Add a new marketplace (prompts for the source) |
| `r` | Remove the highlighted marketplace |
| `u` | Update — re-fetch the marketplace's catalogue |
| `t` | Toggle auto-update for this marketplace |

Auto-update defaults differ by marketplace type:

| Marketplace type | Default auto-update |
|---|---|
| Official Anthropic | On |
| Third-party (any other Git remote) | Off |
| Local-development (`file://` or relative path) | Off |

The toggle is per-marketplace and lives in the user's settings. See [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) for the env-var overrides.

## Errors tab

Lists every plugin currently in an error state along with the reason. Common error categories:

| Error | Meaning |
|---|---|
| Manifest schema error | `plugin.json` failed validation at load time |
| Missing dependency | A plugin in `dependencies[]` isn't installed and couldn't auto-install |
| Range conflict | Two plugins require incompatible versions of the same dep |
| Missing tag | The dep references a `<plugin>--v<X>` tag that doesn't exist on the remote |
| Source unreachable | The marketplace source can't be fetched (network, auth, dead URL) |

Per-error actions:

| Key | Action |
|---|---|
| Enter | View the full error trace and which plugin/marketplace it came from |
| `r` | Retry resolution |
| `u` | Uninstall the offending plugin (last resort) |

Errors here mirror what `/doctor` reports, with the addition of inline retry and uninstall actions.

## Detail views

Pressing Enter on any list item opens its detail view. For a plugin:

- Full description
- README rendering (the plugin's `README.md`)
- Manifest summary (capabilities count: skills, commands, agents, hooks, MCP, LSP)
- Source info (marketplace, version, cache path)
- Per-scope enablement state
- Action buttons (install / enable / disable / uninstall / update)

For a marketplace:

- Source URL or path
- Ref pin
- Last update time
- Plugins listed (each navigable)
- Auto-update toggle

## What the UI is and isn't for

| Use the UI for | Use the CLI for |
|---|---|
| Discovering plugins you don't already know | Scripted / batch installs |
| Eyeballing errors | CI integration |
| One-off enable/disable toggles | Headless `claude -p` test sessions |
| Reading READMEs in context | Bulk operations across many plugins |

For workflows that touch many plugins or need to be reproducible, [`01_claude-plugin-cli.md`](./01_claude-plugin-cli.md) is faster.

## See also

- [`02_built-in-slash-commands.md`](./02_built-in-slash-commands.md) — `/plugin` and friends
- [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) — auto-update toggles per marketplace
- [`../04_marketplaces/`](../04_marketplaces/00_index.md) — what each marketplace source type means
