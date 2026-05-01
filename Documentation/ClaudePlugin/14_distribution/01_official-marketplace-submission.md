# Official marketplace submission

The Anthropic-curated marketplace is the path of least friction for consumers — they install Claude Code, and the marketplace is already there. Submission is via in-app forms.

## Submission portals

Two equivalent forms — submit through whichever is easier:

| Portal | URL |
|---|---|
| Claude.ai | [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit) |
| Claude platform console | [platform.claude.com/plugins/submit](https://platform.claude.com/plugins/submit) |

Both feed into the same review queue. They're not separate marketplaces.

## What gets submitted

Submission is a pointer to your plugin (Git URL, marketplace URL, or repo + plugin path), not a tarball or archive. Reviewers fetch from where you point and read what's there.

| Field | Provided |
|---|---|
| Repository / source URL | Required |
| Plugin path within repo (if not at root) | Required when applicable |
| Suggested marketplace category | Optional |
| Brief reviewer-facing notes | Optional |
| Maintainer contact | Required |

The reviewer reads `plugin.json`, `README.md`, the source for capabilities (skills, commands, agents, hooks, MCP), and verifies the plugin installs and runs.

## What gets reviewed

Before submission, expect reviewers to check:

| Concern | What they look at |
|---|---|
| Manifest correctness | `.claude-plugin/plugin.json` parses, declared capabilities exist on disk |
| Install actually works | Clean-install verification end-to-end |
| Capability quality | Skill descriptions trigger appropriately; commands have useful prompts; hooks don't misbehave |
| Trust posture | No unsandboxed `curl \| sh`, no exfiltrating user data, no obvious supply-chain issues |
| Documentation | README explains what it does, install command works, examples run |
| License | Real SPDX identifier, not `TBD` |

The trust review is the one most often-missed by first-time submitters — see [`../10_trust-and-security.md`](../10_trust-and-security.md) for what to address before submitting.

## Pre-submission checklist

| Item | Why |
|---|---|
| `LICENSE` is a real SPDX license, not `TBD` | Required for distribution |
| `version` is `>= 1.0.0` | Conventional "this is stable" signal |
| `README.md` covers install + a representative example | First read for reviewers and consumers |
| Clean-install loop passes ([`../11_testing-and-iteration/04_clean-install-loop.md`](../11_testing-and-iteration/04_clean-install-loop.md)) | What reviewers will reproduce |
| `dependencies[]` resolve cleanly | Reviewer can't approve if deps are unreachable |
| No secrets, API keys, or PII committed | Obvious, but checked |
| Skill descriptions are specific (not "helps with X") | Affects whether the plugin actually triggers |
| Hooks (if any) don't run obviously dangerous commands | Trust posture |

## After approval

Approved plugins appear in the official marketplace, available immediately to all Claude Code users via `/plugin` Discover. They auto-update by default (since they're hosted by an official Anthropic marketplace) — see [`03_auto-update-controls.md`](./03_auto-update-controls.md).

Updates after the initial approval go through the same review queue. Bump the `version`, push, and re-submit (or wait for the marketplace's update cycle if the review process supports automatic re-fetching of approved plugins — check the submission portal for current rules).

## Alternative: host your own marketplace

If you don't want to wait for review, or your plugin is internal/team-only, just [host your own marketplace](../04_marketplaces/00_index.md). Users add it once with `/plugin marketplace add <source>` and then install plugins as normal.

| Concern | Official marketplace | Self-hosted |
|---|---|---|
| Discoverability | Default for all users | Users must know your URL |
| Auto-update | On by default | Off by default — toggleable |
| Trust signal | Anthropic-reviewed | None — user trusts you directly |
| Iteration speed | Bound by review cycle | Push and pull |
| Suitable for | Public, polished plugins | Team plugins, internal tooling, fast iteration |

Many plugins live in both: the official marketplace for the audience, a self-hosted one for pre-release iteration.

## See also

- [`02_plugin-hints.md`](./02_plugin-hints.md) — recommend your plugin from your own CLI
- [`../04_marketplaces/`](../04_marketplaces/00_index.md) — self-hosting a marketplace
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — the publishing checklist this submission depends on
- Official: [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)
