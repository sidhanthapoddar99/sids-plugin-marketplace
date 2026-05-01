# Distribution

How plugins reach users — once a plugin works, the next concern is "how does someone else find and install it?" Three distinct mechanisms cover the common cases.

## The three mechanisms

| Mechanism | Audience | Effort |
|---|---|---|
| **Submission to the official Anthropic marketplace** | Anyone with Claude Code, no setup | Submit form + review |
| **Host your own marketplace** | Users you tell about it; teams; orgs | One `marketplace.json` in a Git repo |
| **`/plugin-hints` from your own CLI** | Users of an external tool you maintain | Once your plugin is in *some* marketplace |

These compose. A plugin can be in the official marketplace AND your own marketplace AND have CLI hints — a user discovers it through whichever surface they hit first.

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_official-marketplace-submission.md` | Submission portals, what gets reviewed, alternatives |
| 02 | `02_plugin-hints.md` | The `/plugin-hints` mechanism: external CLIs that suggest installs |
| 03 | `03_auto-update-controls.md` | Default auto-update behaviour, per-marketplace toggle, `DISABLE_AUTOUPDATER`, `FORCE_AUTOUPDATE_PLUGINS` |

## Related chapters

- [`../04_marketplaces/`](../04_marketplaces/00_index.md) — what a marketplace looks like, the alternative to submission
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — what to do before submitting
- [`../11_testing-and-iteration/04_clean-install-loop.md`](../11_testing-and-iteration/04_clean-install-loop.md) — verifying the install works for a new consumer
- [`../10_trust-and-security.md`](../10_trust-and-security.md) — what reviewers and consumers care about
