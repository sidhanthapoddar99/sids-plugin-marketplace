---
title: Environment Variables
description: User-controlled env vars that affect Claude Code's runtime — auto-update toggles and marketplace auth tokens
---

# Environment Variables

Env vars in this page are **user-controlled** — set in the user's shell, dotfiles, or CI environment, not in any `settings.json`. They influence Claude Code's runtime: whether it auto-updates itself and its plugins, and whether background marketplace fetches can authenticate to private hosts.

For env vars that plugins themselves consume or expose (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `CLAUDE_PLUGIN_OPTION_<KEY>`, etc.), see [Plugin env vars cheatsheet](../ClaudePlugin/15_reference/01_env-vars-cheatsheet.md).

## Auto-update behaviour

Claude Code auto-updates itself and (for marketplaces opted in) installed plugins at startup. Two env vars control this:

| Var | Effect |
|---|---|
| `DISABLE_AUTOUPDATER=1` | Disables Claude Code auto-update **including** plugin auto-updates |
| `FORCE_AUTOUPDATE_PLUGINS=1` | When combined with `DISABLE_AUTOUPDATER=1`, **keeps** plugin auto-updates while disabling Claude Code's core update |

The combinations:

| `DISABLE_AUTOUPDATER` | `FORCE_AUTOUPDATE_PLUGINS` | Result |
|---|---|---|
| (unset) | (unset) | Default: Claude Code and plugins both auto-update |
| `1` | (unset) | Nothing auto-updates — neither Claude Code nor plugins |
| `1` | `1` | Claude Code stays pinned; plugins continue auto-updating |
| (unset) | `1` | No effect — `FORCE_AUTOUPDATE_PLUGINS` only matters when the autoupdater is disabled |

### Per-marketplace auto-update

Auto-update is **per-marketplace**, not just global. Official Anthropic marketplaces are opted in by default; third-party and local-development marketplaces are opted out by default. Toggle individual marketplaces in the `/plugin` UI (Marketplaces tab → select → toggle auto-update).

The env vars above are the *global* override on top of those per-marketplace toggles. Setting `DISABLE_AUTOUPDATER=1` short-circuits everything regardless of per-marketplace settings.

### When to disable

Common reasons:

| Reason | Setting |
|---|---|
| Locked-down corporate environment, IT manages versions | `DISABLE_AUTOUPDATER=1` |
| Want pinned Claude Code but live plugin development | `DISABLE_AUTOUPDATER=1` + `FORCE_AUTOUPDATE_PLUGINS=1` |
| Air-gapped / no outbound network at startup | `DISABLE_AUTOUPDATER=1` |
| CI/CD where reproducibility matters | `DISABLE_AUTOUPDATER=1` |

## Marketplace auth tokens

Adding a private-marketplace via `/plugin marketplace add` interactively uses your local Git credentials (SSH keys, `.netrc`, OS credential helper). But **background auto-update** runs at session startup without prompts, so it needs ambient credentials in the environment. Set the appropriate token env var(s) for any private host whose marketplaces or plugins you've installed:

| Provider | Env var(s) |
|---|---|
| GitHub | `GITHUB_TOKEN` or `GH_TOKEN` |
| GitLab | `GITLAB_TOKEN` or `GL_TOKEN` |
| Bitbucket | `BITBUCKET_TOKEN` |

Either spelling works for GitHub and GitLab. The token needs read access to the marketplace repo (and to any private plugin repos that marketplace lists by `github`/`url`/`git-subdir` source).

> [!note]
> **These are only required for *background* auto-updates of *private* marketplaces.** Public marketplaces don't need a token. Private marketplaces added interactively via `/plugin marketplace add` use your normal Git auth and don't need these vars unless you also want auto-update to work in the background.

If a token is missing or insufficient for an enabled private marketplace, the auto-update silently skips that marketplace and surfaces the failure under `/doctor`.

## Other Claude-Code-relevant env vars

A few more env vars shape session behaviour. They're set by the user (or their IT department), not by plugins:

| Var | Effect |
|---|---|
| `ANTHROPIC_API_KEY` | API key for direct Anthropic API access (alternative to in-app login) |
| `CLAUDE_CONFIG_DIR` | Override the default `~/.claude/` config directory |
| `NO_COLOR` | Disables ANSI colour output (standard convention) |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | Standard proxy configuration honoured by the underlying HTTP client and `git` shell-outs |

The official settings reference lists more — this page only covers the ones that interact with the plugin / marketplace system. Treat the official docs as the source of truth for the full list.

## What env vars *cannot* do

| Goal | Don't reach for env vars |
|---|---|
| Pin a plugin to a specific version | Use `enabledPlugins` with version specifier, or pin via `ref`/`sha` in marketplace.json |
| Disable a single plugin | `/plugin disable <name>@<mkt>` (sets the boolean to `false`) |
| Restrict which marketplaces users can add | Use `strictKnownMarketplaces` at managed scope (see [Plugin-Related Settings](./05_plugin-related-settings.md)) |
| Grant a tool permission | Use `permissions.allow` in `settings.json` (see [Permissions and Keybindings](./03_permissions-and-keybindings.md)) |

The env-var surface is small and policy-light by design. Most behaviour is configured in `settings.json`, not the environment.

## See also

- [Settings Files and Precedence](./01_settings-files-and-precedence.md) — alternative to env vars: per-scope JSON
- [Plugin env vars cheatsheet](../ClaudePlugin/15_reference/01_env-vars-cheatsheet.md) — env vars that plugins themselves use
- Official: [Auto-update configuration](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)
- Official: [Claude Code settings](https://code.claude.com/docs/en/settings)
