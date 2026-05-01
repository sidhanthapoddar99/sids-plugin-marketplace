# `/plugin-hints`

A mechanism that lets external CLI tools tell Claude Code "if the user is doing X, recommend installing my plugin." Claude Code surfaces those hints as install suggestions in-session.

## The shape

| Side | Role |
|---|---|
| External CLI | Emits hints in the right format when invoked |
| Claude Code | Picks up hints, evaluates context, surfaces install suggestions to the user |
| User | Sees a contextual prompt: "Install `<plugin>` for richer support of this workflow?" |

The bridge is whatever channel Claude Code is already watching when external CLIs run — typically tool-call output that conventionally includes hint metadata.

## When to use this

You're already maintaining an external CLI tool that integrates with Claude Code (for example, a developer-facing tool whose users frequently end up in Claude Code sessions). You've also published a plugin in some marketplace that improves the experience for those users. Plugin-hints is the mechanism that bridges them: your CLI's output suggests the plugin, Claude Code picks up the suggestion.

Without this, your CLI users have to find your plugin themselves.

## Prerequisites

| Prerequisite | Detail |
|---|---|
| The plugin must be in a marketplace | Either the official marketplace or any self-hosted one Claude Code can resolve |
| Plugin name and marketplace name are stable | Hints reference them by name |
| Your CLI is invoked from inside a Claude Code session | The hint mechanism only fires when Claude Code is the outer process |
| Users haven't already installed the plugin | Hints are skipped if the plugin is already enabled |

## Setup pattern

The general pattern (specifics in the official `/plugin-hints` doc):

1. Your CLI detects when its output is being consumed by Claude Code (via env var, parent-process check, or explicit flag)
2. When relevant — the CLI command is one your plugin would meaningfully improve — your CLI emits a structured hint alongside its normal output
3. Claude Code, watching tool-call output, parses the hint and queues an install suggestion
4. At a natural break in the conversation, Claude Code presents the suggestion to the user with one-tap install

The hint encoding and the exact emission format are Claude Code-version-specific; consult the official docs linked below for the current schema.

## What a hint typically carries

| Field | Purpose |
|---|---|
| Plugin name | Which plugin to install |
| Marketplace identifier | Which marketplace it lives in |
| Reason / context | A short string explaining why the suggestion fires here |
| Source URL (optional) | Marketplace `add` source if not already known to the user |

Claude Code presents the reason verbatim to the user — keep it specific to the workflow your CLI just helped with, not generic marketing copy.

## What it is not

| Misconception | Reality |
|---|---|
| A separate distribution channel | The plugin still has to be in a marketplace; hints just suggest installing it |
| A way to bypass user consent | Users explicitly approve any install. Hints are suggestions, not auto-installs |
| A way to push updates | Auto-updates are independent. See [`03_auto-update-controls.md`](./03_auto-update-controls.md) |
| Available without the marketplace step | A plugin not in any marketplace can't be hinted at |

## Trust and consent

Plugin hints can't install anything on their own. The user always sees:

- The plugin name
- The marketplace it comes from
- The reason your CLI gave for the suggestion
- An explicit accept / decline action

Bad-faith hints (suggesting a plugin unrelated to what the CLI just did) damage trust quickly and surface in the user-facing reason text. Keep hints scoped to genuine value-add.

## Comparison with `extraKnownMarketplaces`

Both nudge users toward marketplaces / plugins they don't have, but the surface differs:

| Surface | When it fires | Source |
|---|---|---|
| `/plugin-hints` | Mid-session, in response to specific CLI output | External tool integration |
| `extraKnownMarketplaces` | At trust-prompt time on a project folder | Project's `.claude/settings.json` |

`/plugin-hints` is right for "I'm a CLI maintainer suggesting a plugin." `extraKnownMarketplaces` is right for "this repo expects a specific team marketplace." See [`../04_marketplaces/`](../04_marketplaces/00_index.md) for the team-marketplace pattern.

## See also

- [`01_official-marketplace-submission.md`](./01_official-marketplace-submission.md) — getting the plugin into a marketplace in the first place
- [`../04_marketplaces/`](../04_marketplaces/00_index.md) — the marketplace prerequisite
- Official: [Recommend your plugin from your CLI](https://code.claude.com/docs/en/plugin-hints)
