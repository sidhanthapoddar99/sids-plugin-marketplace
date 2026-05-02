# sids-plugin-marketplace

A community-friendly Claude Code plugin marketplace, maintained by Sid.

## Purpose

A marketplace is a catalogue of plugins that Claude Code users can install with one command. **This** marketplace serves three purposes:

1. **Distribute Sid's in-house plugins** — `ai-toolkit-dev` (a toolkit for authoring plugins, marketplaces, and skills) and `monorepo-setup` (personal monorepo conventions). Both are kept in this repo under `plugins/`.
2. **Curate community plugins** — once submissions land, third-party plugins are listed alongside the in-house ones. Users get a single `add` command for everything in the catalogue.
3. **Carry a substantive reference doc set** — `Documentation/ClaudePlugin/` and `Documentation/ClaudeSettings/` are open-source references for the Claude Code plugin ecosystem, fact-checked against the official Anthropic docs and the upstream `anthropics/claude-plugins-official` repo. Useful to anyone authoring plugins, not just consumers of this marketplace.

---

## Installing

Inside a Claude Code session, register the marketplace once:

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
```

Then install whichever plugins you want:

```
/plugin install ai-toolkit-dev@sids-plugin-marketplace
/plugin install monorepo-setup@sids-plugin-marketplace
```

The `@sids-plugin-marketplace` suffix is optional if no other registered marketplace ships a plugin of the same name.

To pin to a specific marketplace ref:

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace#v1.0
```

---

## Plugins in this marketplace

| Plugin | Description | Status |
|---|---|---|
| [`ai-toolkit-dev`](plugins/ai-toolkit-dev) | Toolkit for authoring Claude Code plugins, marketplaces, and skills | Work in progress |
| [`monorepo-setup`](plugins/monorepo-setup) | Personal monorepo conventions: env vars, config files, docker-compose, scripts, database/alembic, secrets management | Work in progress |

---

## Submitting your plugin

Submissions are by **pull request**. The flow:

1. **Fork this repo.**
2. **Append your plugin entry** to the `plugins` array in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Keep the existing entries in place; just add yours at the end.
3. **Open a PR.** Title: `submission: <your-plugin-name>`. Describe what your plugin does in 1–2 paragraphs in the PR body, and link to your plugin's repo and `plugin.json`.

That's it. The marketplace itself only carries the index — your plugin lives in your own repo, and the entry tells Claude Code where to fetch it.

### Minimum entry

```json
{
  "name": "your-plugin-name",
  "source": {
    "source": "github",
    "repo": "your-username/your-plugin-repo"
  },
  "description": "One-sentence description of what the plugin does"
}
```

### Optional fields

| Field | Use |
|---|---|
| `version` | Pin to a specific git tag (e.g. `"version": "1.2.0"` resolves to the `your-plugin-name--v1.2.0` tag in your repo) |
| `category` | Free-form category for `/plugin` UI grouping |
| `tags` | Array of search tags |
| `author` | `{ "name": "...", "email": "...", "url": "..." }`. Falls back to the marketplace `owner` if absent |
| `homepage` | Project URL |
| `strict` | `true` to require exact-match version resolution |

### Other source forms

The `github` form above is the most common. The `source` field also accepts `url` (any git repo, GitLab/Bitbucket/etc.), `git-subdir` (plugin in a monorepo subdirectory), `npm` (plugin published as an npm package), or a relative path string. See the source-types reference: [`Documentation/ClaudePlugin/04_marketplaces/02_source-types.md`](Documentation/ClaudePlugin/04_marketplaces/02_source-types.md).

### Submission review

I'll check that:

- the repo has a working `.claude-plugin/plugin.json`
- the plugin loads cleanly via `claude --plugin-dir <your-repo>`
- the description and license are honest

On approval, your PR is merged and the marketplace ref is bumped — users will see your plugin in `/plugin marketplace update`.

---

## Documentation

This repo carries a substantial reference set on the Claude Code plugin ecosystem, useful whether you're authoring a plugin or operating a marketplace.

### `Documentation/ClaudePlugin/` — 16 chapters covering the plugin layer

| Chapter | Topic |
|---|---|
| [`01_overview`](Documentation/ClaudePlugin/01_overview.md) | The three layers — model, runtime, packaging |
| [`02_mental-model/`](Documentation/ClaudePlugin/02_mental-model/) | What the model sees vs. what the runtime sees, naming and namespacing |
| [`03_storage-and-scope/`](Documentation/ClaudePlugin/03_storage-and-scope/) | Cache layout, data dir, scope union (`Managed > Local > Project > User`), env vars |
| [`04_marketplaces/`](Documentation/ClaudePlugin/04_marketplaces/) | `marketplace.json` anatomy, source types, ref/sha pinning, release channels, cross-marketplace deps |
| [`05_plugin-anatomy/`](Documentation/ClaudePlugin/05_plugin-anatomy/) | Directory layout, manifest fields, `userConfig`, plugin-shipped settings |
| [`06_capabilities/`](Documentation/ClaudePlugin/06_capabilities/) | Every capability surface — skills, slash commands, subagents, hooks, MCP, LSP, monitors, channels, themes, output styles, bin wrappers |
| [`07_lifecycle-and-runtime/`](Documentation/ClaudePlugin/07_lifecycle-and-runtime/) | Install flow, activation, hot-swap matrix, updates, garbage collection, validation |
| [`08_composition-patterns/`](Documentation/ClaudePlugin/08_composition-patterns/) | Hand-author / depend / soft-fork decision matrix |
| [`09_versioning-and-publishing/`](Documentation/ClaudePlugin/09_versioning-and-publishing/) | SemVer, the `<plugin>--v<X.Y.Z>` tag convention, version resolution, release loop |
| [`10_trust-and-security`](Documentation/ClaudePlugin/10_trust-and-security.md) | Unsandboxed model, path-traversal limit, managed allowlist |
| [`11_testing-and-iteration/`](Documentation/ClaudePlugin/11_testing-and-iteration/) | `--plugin-dir`, headless mode, benchmarking, the clean-install loop |
| [`12_cli-and-ui/`](Documentation/ClaudePlugin/12_cli-and-ui/) | The `claude plugin` CLI, built-in slash commands, `/plugin` UI |
| [`13_uninstall-and-cleanup`](Documentation/ClaudePlugin/13_uninstall-and-cleanup.md) | Uninstall mechanics, cache wipe, `--keep-data`, `--prune` |
| [`14_distribution/`](Documentation/ClaudePlugin/14_distribution/) | Official marketplace submission, `/plugin-hints`, auto-update controls |
| [`15_reference/`](Documentation/ClaudePlugin/15_reference/) | Env-vars cheatsheet, settings keys, frontmatter flags, legacy/migration |
| [`16_examples/`](Documentation/ClaudePlugin/16_examples/) | Worked plugins and marketplaces — minimal, dogfood, catalogue, soft-fork |

### `Documentation/ClaudeSettings/` — companion: the settings-side boundary

Plugins can ship many things, but **not** the user's main `statusLine`, `permissions`, `keybindings`, or the `enabledPlugins` boolean itself. This small companion doc set covers the settings-side surface — six files documenting where plugin-related settings live (`enabledPlugins`, `extraKnownMarketplaces`, `strictKnownMarketplaces`, `pluginConfigs`), the four scopes (Managed / User / Project / Local), and the keys plugins cannot ship as defaults.

[`Documentation/ClaudeSettings/`](Documentation/ClaudeSettings/) →

### When to read what

| Situation | Start here |
|---|---|
| First time encountering Claude Code plugins | [`01_overview`](Documentation/ClaudePlugin/01_overview.md) → [`02_mental-model/`](Documentation/ClaudePlugin/02_mental-model/) |
| Authoring your first plugin | [`05_plugin-anatomy/`](Documentation/ClaudePlugin/05_plugin-anatomy/) → [`06_capabilities/`](Documentation/ClaudePlugin/06_capabilities/) → [`16_examples/01_minimal-plugin`](Documentation/ClaudePlugin/16_examples/01_minimal-plugin.md) |
| Setting up a marketplace | [`04_marketplaces/`](Documentation/ClaudePlugin/04_marketplaces/) → [`16_examples/02_dogfood-marketplace`](Documentation/ClaudePlugin/16_examples/02_dogfood-marketplace.md) |
| Cutting a release | [`09_versioning-and-publishing/`](Documentation/ClaudePlugin/09_versioning-and-publishing/) |
| Debugging a plugin that won't load | [`12_cli-and-ui/`](Documentation/ClaudePlugin/12_cli-and-ui/) → [`07_lifecycle-and-runtime/06_schema-validation`](Documentation/ClaudePlugin/07_lifecycle-and-runtime/06_schema-validation.md) |
| Org-restricted environment | [`Documentation/ClaudeSettings/05_plugin-related-settings`](Documentation/ClaudeSettings/05_plugin-related-settings.md) |

For task-oriented authoring (the *how-to* rather than the *what exists*), the `ai-toolkit-dev` plugin is the companion — install it from this marketplace.

---

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # the marketplace manifest
├── CLAUDE.md                         # agent guidance for working in this repo
├── Documentation/
│   ├── ClaudePlugin/                 # 16-chapter reference on the plugin ecosystem
│   └── ClaudeSettings/               # companion: settings.json keys at the user/project/managed boundary
├── plugins/
│   ├── ai-toolkit-dev/               # plugin authoring toolkit
│   └── monorepo-setup/               # personal monorepo conventions
├── scripts/                          # marketplace-level maintainer tooling
└── LICENSE                           # MIT
```

---

## Maintainer

Sid — `developer@neuralabs.org`

Issues and PRs welcome at <https://github.com/sidhanthapoddar99/sids-plugin-marketplace>.

---

## License

MIT — see [`LICENSE`](LICENSE).

Some content under `plugins/ai-toolkit-dev/skills/` is vendored from upstream [`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) (Apache-2.0) with provenance recorded in `plugins/ai-toolkit-dev/.upstream/manifest.json`. Those upstream attributions stay intact.
