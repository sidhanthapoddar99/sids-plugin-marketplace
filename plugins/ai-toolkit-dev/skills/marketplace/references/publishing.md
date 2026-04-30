# Publishing a marketplace

Once `.claude-plugin/marketplace.json` is correct, publishing means **making it reachable** and **pinning plugin versions** so consumers get reproducible installs.

## Hosting options

### GitHub (most common)

Push the repo containing `.claude-plugin/marketplace.json`. Users add it with the `owner/repo` shorthand:

```
/plugin marketplace add owner/repo
```

Pin to a tag or branch with `#<ref>`:

```
/plugin marketplace add owner/repo#v2.0
```

### Arbitrary git host

```
/plugin marketplace add https://gitlab.example.com/team/marketplace.git
```

Pin with `#ref`:

```
/plugin marketplace add https://gitlab.example.com/team/marketplace.git#v2.0
```

### Static URL

A `marketplace.json` served directly (CDN, S3 bucket, raw GitHub blob):

```
/plugin marketplace add https://example.com/marketplace.json
```

The URL must serve the JSON directly — no HTML wrapping. **Static-URL marketplaces cannot use relative-path plugin sources** — the surrounding repo isn't downloaded. Use `github`, `url`, `git-subdir`, or `npm` for plugins instead.

### Local directory

For development and pre-release testing:

```
/plugin marketplace add ./my-marketplace
```

### Private repositories

For private marketplaces, use any git server with credential access. Claude Code shells out to `git`, which uses your `.netrc`, SSH keys, or credential helper.

For background auto-updates (which run at startup without prompts), set the appropriate token env var:

| Provider | Env var(s) |
|---|---|
| GitHub | `GITHUB_TOKEN` or `GH_TOKEN` |
| GitLab | `GITLAB_TOKEN` or `GL_TOKEN` |
| Bitbucket | `BITBUCKET_TOKEN` |

## Marketplace ref vs plugin ref — they're independent

Two distinct things to pin:

- **Marketplace source** — where to fetch `marketplace.json` itself. Set when the user runs `/plugin marketplace add` (or via `extraKnownMarketplaces` in `.claude/settings.json`). Supports `ref` (branch/tag) but **not `sha`**.
- **Plugin source** — set in each entry's `source` field inside `marketplace.json`. Supports both `ref` and `sha`.

A marketplace at `acme-corp/plugin-catalog@v1.2` (marketplace source pinned to tag `v1.2`) can list a plugin from `acme-corp/code-formatter#sha:abcdef…` (plugin source pinned to a commit). They are pinned independently.

## Pinning plugin versions

Two complementary mechanisms:

### Pin via `ref` / `sha` in the source

Works with all git-based source types (`github`, `url`, `git-subdir`):

```json
{
  "name": "my-plugin",
  "source": {
    "source": "github",
    "repo": "me/my-plugin",
    "ref": "v2.1.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

`ref` resolves at install time (slow-moving). `sha` pins to an exact commit (immutable). Use both together when you want the readability of a tag plus the immutability of a SHA.

### Pin via `version` field

```json
{
  "name": "my-plugin",
  "source": { "source": "github", "repo": "me/my-plugin" },
  "version": "2.1.0"
}
```

`version` controls **cache identity**. If the resolved version matches what a user has cached, `/plugin update` is a no-op. See [`schema.md`](schema.md#version-resolution) for the exact resolution order.

> **Don't set `version` in both `plugin.json` and the marketplace entry.** `plugin.json` always wins, so a stale value there silently masks the marketplace pin. Set it in *one* place.

## Release channels (stable / latest)

Two marketplaces pointing at different refs of the same plugin repos. Assign each marketplace to a different user group via managed settings.

```json
// stable-tools/marketplace.json
{
  "name": "stable-tools",
  "owner": { "name": "Acme" },
  "plugins": [{
    "name": "code-formatter",
    "source": { "source": "github", "repo": "acme-corp/code-formatter", "ref": "stable" }
  }]
}
```

```json
// latest-tools/marketplace.json
{
  "name": "latest-tools",
  "owner": { "name": "Acme" },
  "plugins": [{
    "name": "code-formatter",
    "source": { "source": "github", "repo": "acme-corp/code-formatter", "ref": "latest" }
  }]
}
```

> Each channel must resolve to a **different version**. If you set `version` explicitly, `plugin.json` must declare a different version at each ref. If you omit `version`, the distinct commit SHAs already distinguish channels. Two refs that resolve to the same `version` string are treated as identical and updates are skipped.

Full file: [`../examples/release-channels.json`](../examples/release-channels.json).

## Cache and refresh

After `/plugin marketplace add`:

- The manifest is cached at `~/.claude/plugins/marketplaces/<name>/`.
- Plugin sources are cached at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.

```
/plugin marketplace update <name>     # refresh one
/plugin marketplace update            # refresh all
```

Refresh skips seed-managed marketplaces (read-only).

## Pre-populating for containers / CI

Set `CLAUDE_CODE_PLUGIN_SEED_DIR` to a directory mirroring `~/.claude/plugins/`:

```
$CLAUDE_CODE_PLUGIN_SEED_DIR/
  known_marketplaces.json
  marketplaces/<name>/...
  cache/<marketplace>/<plugin>/<version>/...
```

Build the seed by running Claude Code once with `CLAUDE_CODE_PLUGIN_CACHE_DIR` pointed at the build target:

```bash
CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed claude plugin marketplace add your-org/plugins
CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed claude plugin install my-tool@your-plugins
```

At runtime, set `CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/claude-seed`. The seed is read-only — auto-updates are disabled for seed marketplaces.

## Validation at publish time

```bash
claude plugin validate .
```

Recommended: include `"$schema": "https://anthropic.com/claude-code/marketplace.schema.json"` in your `marketplace.json` so editors validate as you type.

## Network resilience

For offline / airgapped environments where `git pull` will fail and you don't want Claude Code to wipe the stale cache:

```bash
export CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1
```

For slow networks where the default 120s git timeout is too tight:

```bash
export CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=300000   # 5 min
```

## License signaling

Marketplaces themselves don't declare a license. Each plugin's `plugin.json` (or marketplace entry, if `strict: false`) declares its own via the `license` field. Include a `LICENSE` file at the marketplace repo root and a `license` line on every plugin entry, so consumers can audit what they're installing.
