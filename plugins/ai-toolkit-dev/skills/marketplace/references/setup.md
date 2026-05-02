# Building a marketplace from scratch

This is the task flow for creating a new `.claude-plugin/marketplace.json` from zero. For field-level details, see [`schema.md`](schema.md). For full working files, see [`../examples/`](../examples/).

## Decide the layout first

Three common shapes:

1. **Self-hosted (dogfood)** — plugins live in the same repo as the marketplace. Use relative-path sources (`"./plugins/<name>"`). Example: [`../examples/dogfood.json`](../examples/dogfood.json).
2. **Catalogue** — marketplace points at plugins hosted in other repos / npm. Use `github`, `url`, `git-subdir`, or `npm` sources. Example: [`../examples/catalogue.json`](../examples/catalogue.json).
3. **Hybrid** — some plugins hosted in-repo, some external. Mix relative-path entries with object-source entries in the same `plugins` array.

Pick based on whether you control the plugin source code. If yes, dogfood. If you're indexing other people's work, catalogue.

## Step 1: scaffold the file

```
my-marketplace/
└── .claude-plugin/
    └── marketplace.json
```

Smallest valid file (see [`../examples/minimal.json`](../examples/minimal.json)):

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "my-marketplace",
  "description": "What this marketplace offers",
  "owner": { "name": "Your Name", "email": "you@example.com" },
  "plugins": []
}
```

Save as `.claude-plugin/marketplace.json` at the root of a git repo. That's installable with `/plugin marketplace add ./my-marketplace`.

> Pick a `name` that isn't on the [reserved list](schema.md#reserved-marketplace-names). `claude-plugins-official` and the other Anthropic-claimed names will be rejected by Claude.ai's marketplace sync.

## Step 2: add the first plugin entry

Pick the source type that matches where your plugin lives. The five forms are documented in [`schema.md`](schema.md#source-types). Quick chooser:

| Where the plugin lives | Use |
|---|---|
| Same repo as the marketplace | string source (relative path) |
| Top of a GitHub repo | `github` |
| Subdirectory of any git repo (incl. monorepos) | `git-subdir` |
| Top of a non-GitHub git repo | `url` |
| npm package | `npm` |

Minimal entry:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "What this plugin does"
}
```

Add `version`, `author`, `category`, `keywords`, `tags`, `homepage`, `license` etc. as needed. See [`schema.md`](schema.md#standard-metadata-fields-optional) for the full optional-field list.

## Step 3: decide who owns the components

Two modes:

- **`strict: true` (default)** — each plugin source has its own `.claude-plugin/plugin.json` declaring components (skills, agents, hooks, etc.). Marketplace entry can *add* components on top. This is the default and matches the standard plugin-authoring workflow.
- **`strict: false`** — marketplace entry declares everything inline (`commands`, `agents`, `hooks`, `mcpServers`, `lspServers`, `skills`). Plugin source is just raw files. Used when the marketplace operator curates a third-party repo differently than its author intended.

See [`../examples/inline-plugin.json`](../examples/inline-plugin.json) for a fully inline definition.

## Step 4: validate before publishing

Add the marketplace locally and surface errors:

```bash
claude plugin marketplace add ./
claude plugin list --available --json | jq '.errors'
```

The structured `errors` field surfaces duplicate plugin names, JSON syntax errors, malformed YAML frontmatter, broken `hooks/hooks.json`, and `..` in relative paths. The `/plugin` UI's Errors tab shows the same set interactively. See [`schema.md`](schema.md#validation) for the error catalogue.

## Step 5: install locally and smoke-test

```bash
claude plugin marketplace add ./my-marketplace
claude plugin install my-plugin@my-marketplace
```

Run a representative skill / agent / command. If everything works, push to your git host and proceed to [`publishing.md`](publishing.md).

## What `marketplace.json` does NOT control

- It does not declare what's *inside* a plugin — that's `plugin.json` per plugin (unless `strict: false`, in which case the marketplace entry is the declaration).
- It does not enforce versioning policy — version pinning is per-plugin via the `version` field, not marketplace-wide.
- It does not grant capabilities to plugins — Claude Code's permission and scope rules apply identically regardless of which marketplace a plugin came from.
