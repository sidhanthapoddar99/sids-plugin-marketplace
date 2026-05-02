# sids-plugin-marketplace

Personal Claude Code plugin marketplace maintained by Sid.

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
```

---

## Submitting a plugin

If you'd like your plugin listed in this marketplace, **open a GitHub issue** with the entry as a copy-pasteable JSON snippet. The snippet should be ready to drop directly into the `plugins` array of [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) — no reformatting needed on my end.

Open: <https://github.com/sidhanthapoddar99/sids-plugin-marketplace/issues/new>

### Issue template

**Title:** `submission: <your-plugin-name>`

**Body:**

````markdown
### Plugin entry (paste as-is into marketplace.json)

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

### About the plugin

- **What it does:** 1–2 paragraphs
- **Plugin manifest:** link to your `.claude-plugin/plugin.json` in the repo
- **License:** SPDX identifier (e.g. `MIT`, `Apache-2.0`)
- **Maintenance intent:** ongoing / one-shot / experimental
````

### Optional fields you may add to the snippet

| Field | Use |
|---|---|
| `version` | Pin to a specific git tag (e.g. `"version": "1.2.0"` resolves to the `your-plugin-name--v1.2.0` tag in your repo) |
| `category` | Free-form category for `/plugin` UI grouping |
| `tags` | Array of search tags |
| `strict` | `true` to require exact-match version resolution |

### Other source forms

The `github` form above is the most common. The `source` field also accepts `url`, `git-subdir`, `npm`, or a relative string (only relevant for plugins hosted *inside this repo*). See the marketplace source-types reference: [`Documentation/ClaudePlugin/04_marketplaces/02_source-types.md`](Documentation/ClaudePlugin/04_marketplaces/02_source-types.md).

### Submission review

Submissions are reviewed manually. I'll check that:

- the repo has a working `.claude-plugin/plugin.json`
- the plugin loads cleanly via `claude plugin install --plugin-dir <your-repo>`
- the description and license are honest

Approval = your snippet is appended to `marketplace.json` and the marketplace ref is bumped.

---

## Plugins in this marketplace

| Plugin | Description | Status |
|---|---|---|
| [`ai-toolkit-dev`](plugins/ai-toolkit-dev) | Toolkit for authoring Claude Code plugins, marketplaces, and skills | Work in progress (scaffold + plan) |
| [`monorepo-setup`](plugins/monorepo-setup) | Personal monorepo conventions: env vars, config files, docker-compose, scripts, database/alembic, secrets management | Work in progress (scaffold) |

---

## Soft-fork pattern

`ai-toolkit-dev` vendors content from upstream [`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) using the soft-fork + upstream tracking pattern. Drift detection lives at the **marketplace level** (`scripts/ai-toolkit-dev-check-upstream`), not inside the plugin — consumers of the plugin shouldn't have to think about this.

See [`CLAUDE.md`](CLAUDE.md) for when Claude triggers a drift check, and [`Documentation/ClaudePlugin/08_composition-patterns/03_soft-fork.md`](Documentation/ClaudePlugin/08_composition-patterns/03_soft-fork.md) for the pattern itself.

---

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # the marketplace manifest
├── CLAUDE.md                         # agent guidance (upstream check, scope rules)
├── Documentation/                    # reference docs on plugin/marketplace internals + Claude Code settings
│   ├── ClaudePlugin/                 #   16 chapters on the plugin ecosystem
│   └── ClaudeSettings/               #   companion: settings.json keys at the user/project/managed boundary
├── plugins/
│   ├── ai-toolkit-dev/               # plugin authoring toolkit
│   └── monorepo-setup/               # personal monorepo conventions
└── scripts/                          # marketplace-level maintainer tooling
    └── ai-toolkit-dev-check-upstream # per-plugin soft-fork drift checker
```

---

## Maintainer

Sid — `developer@neuralabs.org`

## License

TBD — pending decision before first release. Vendored upstream content (under `plugins/ai-toolkit-dev/skills/.../topics/` and `plugins/ai-toolkit-dev/skills/skill-creator/`) remains Apache 2.0; in-house content's license to be set.
