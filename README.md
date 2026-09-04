# sids-plugin-marketplace

A community-friendly plugin marketplace, maintained by Sid. It ships to Claude Code and Codex CLI.

## Purpose

A marketplace is a catalogue of plugins that users can install with one command. **This** marketplace serves three purposes:

1. **Distribute Sid's in-house plugins** — `project-setup` (personal project / monorepo conventions) is kept in this repo under `plugins/`. `agent-ks` and `uvenv` are listed here and live in their own repos.
2. **Curate community plugins** — once submissions land, third-party plugins are listed alongside the in-house ones. Users get a single `add` command for everything in the catalogue.
3. **Carry a short reference doc set** — `Documentation/` is a ten-file reference on how plugins, marketplaces and skills work across Claude Code, Codex, Hermes and OpenCode. Written in simple technical English for humans and AI agents alike.

---

## Installing

This marketplace ships to two hosts: **Claude Code** and **Codex CLI**.

### Claude Code

Inside a Claude Code session, register the marketplace once:

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
```

Then install whichever plugins you want:

```
/plugin install project-setup@sids-plugin-marketplace
/plugin install instruction-writing@sids-plugin-marketplace
/plugin install agent-ks@sids-plugin-marketplace
/plugin install uvenv@sids-plugin-marketplace
```

The `@sids-plugin-marketplace` suffix is optional if no other registered marketplace ships a plugin of the same name.

To pin to a specific marketplace ref:

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace#v1.0
```

### Codex CLI

Register the marketplace, then install what you want:

```
codex plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
codex plugin add project-setup@sids-plugin-marketplace
codex plugin add instruction-writing@sids-plugin-marketplace
codex plugin add agent-ks@sids-plugin-marketplace
codex plugin add uvenv@sids-plugin-marketplace
```

Start a new thread after installing — that is when Codex picks up new skills.

All four plugins are listed for Codex. `project-setup` and `instruction-writing` live in this repo and have their
own `.codex-plugin/plugin.json`. `agent-ks` and `uvenv` live in their own repos, so
their Codex entries point at those repos and carry the display name inline.

Requires Codex CLI 0.147 or later. Check with `codex --version`.

---

## Plugins in this marketplace

| Plugin | Description | Status |
|---|---|---|
| [`project-setup`](plugins/project-setup) | Architectural decision-maker for repos — new and existing. Layout, env/config split, docker, design tokens, ML orchestration, mobile/desktop. Bootstrap AND restructure. | Work in progress |
| [`instruction-writing`](plugins/instruction-writing) | How to write instruction files for AI agents: CLAUDE.md, AGENTS.md, rules files, SKILL.md bodies, references, briefs. Ten rules with their reasons, a review rubric, before-and-after examples. | Released (v0.1.0) |
| `uvenv` ([repo](https://github.com/sidhanthapoddar99/uvenv)) | Operating manual for `uvenv` — bash/zsh wrapper around mise + uv that gives conda-style named global Python venvs you can activate from anywhere | Released (v0.3.0) |
| `agent-ks` ([repo](https://github.com/sidhanthapoddar99/agent-knowledge-system)) | Operating manual for the agent-knowledge-system framework — docs, issues, artifacts skills, the `agent-ks` CLI dispatcher, scaffolding commands. Formerly `documentation-guide` | Released (v0.6.0) |

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

The `github` form above is the most common. The `source` field also accepts `url` (any git repo, GitLab/Bitbucket/etc.), `git-subdir` (plugin in a monorepo subdirectory), `npm` (plugin published as an npm package), or a relative path string. See [`Documentation/03_claude-code-marketplaces.md`](Documentation/03_claude-code-marketplaces.md).

### Submission review

I'll check that:

- the repo has a working `.claude-plugin/plugin.json`
- the plugin loads cleanly via `claude --plugin-dir <your-repo>`
- the description and license are honest

On approval, your PR is merged and the marketplace ref is bumped — users will see your plugin in `/plugin marketplace update`.

---

## Documentation

`Documentation/` is ten files. Start at [`00_index.md`](Documentation/00_index.md).

| File | Read this when |
|---|---|
| [`01_concepts`](Documentation/01_concepts.md) | You want the platform-neutral definitions of skill, plugin and marketplace |
| [`02_claude-code-plugins`](Documentation/02_claude-code-plugins.md) | You write, install or debug a Claude Code plugin |
| [`03_claude-code-marketplaces`](Documentation/03_claude-code-marketplaces.md) | You run a Claude Code marketplace or pin a source |
| [`04_codex`](Documentation/04_codex.md) | You ship a plugin or marketplace to Codex CLI |
| [`05_hermes`](Documentation/05_hermes.md) | You write or share a skill for Hermes Agent |
| [`06_opencode`](Documentation/06_opencode.md) | You write a plugin or skill for OpenCode |
| [`07_skills-portable`](Documentation/07_skills-portable.md) | You want one skill that works on every host |
| [`08_this-marketplace`](Documentation/08_this-marketplace.md) | You add a plugin to this repo or cut a release |
| [`09_comparison`](Documentation/09_comparison.md) | You need the side-by-side tables |

For skill authoring, use the `skill-creator` skill that ships with Claude Code.

---

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # the marketplace manifest — Claude Code
├── .agents/plugins/marketplace.json  # the marketplace manifest — Codex, kept in sync by hand
├── CLAUDE.md                         # agent guidance for working in this repo
├── Documentation/                    # ten-file reference: plugins, marketplaces, skills across four hosts
├── plugins/
│   ├── project-setup/                # personal project / monorepo conventions
│   └── instruction-writing/          # how to write CLAUDE.md, AGENTS.md, skills, briefs
└── LICENSE                           # MIT
```

---

## Maintainer

Sid — `developer@neuralabs.org`

Issues and PRs welcome at <https://github.com/sidhanthapoddar99/sids-plugin-marketplace>.

---

## License

MIT — see [`LICENSE`](LICENSE).
