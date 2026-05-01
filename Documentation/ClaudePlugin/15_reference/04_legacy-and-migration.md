# Legacy patterns and migration

Two patterns predate the modern plugin model and still work, but newer authors should know which is current. Both still load identically — the migration is mostly about following convention.

## 1. Flat `commands/<name>.md` — the original slash-command layout

### What it is

The earlier convention placed every slash command at `commands/<name>.md`:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
└── commands/
    ├── review.md
    ├── deploy.md
    └── test.md
```

Each markdown file (filename minus `.md`) becomes one slash command. The frontmatter / argument-substitution shape is identical to the modern form.

### What replaced it

The current convention is `skills/<name>/SKILL.md` — one folder per skill (or skill-paired command), with optional `references/` and `scripts/` subfolders for progressive disclosure.

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── review/
        ├── SKILL.md
        ├── references/
        │   └── owasp-top-10.md
        └── scripts/
            └── git-diff-base.sh
```

### Why the change

| Old `commands/foo.md` | New `skills/foo/SKILL.md` |
|---|---|
| One body file, no progressive disclosure | Body is triage; references load on demand |
| Flat folder grows linearly | Each capability is its own folder, easier to manage |
| No place for bundled references / scripts that aren't `bin/` | `references/` + `scripts/` belong to the skill |
| Triggered only as `/foo` | Triggers on description match (model-invoked) **and** as `/skills foo` if exposed |

### Both still load

Claude Code reads both layouts. A single plugin can mix them — some legacy commands under `commands/`, new skill+command pairs under `skills/`. Nothing breaks.

That said: **new plugins should use the skills layout exclusively**. The flat `commands/` directory is preserved for compatibility, not encouraged.

### Migration path

1. For each `commands/<name>.md`, decide whether it's "command-only" (one-shot trigger, no body of conceptual material) or "skill+command" (the command needs broader teaching context):
   - **Command-only**: leave it under `commands/<name>.md`, or move to `skills/<name>/SKILL.md` with the same body.
   - **Skill+command**: create `skills/<name>/SKILL.md` with the conceptual body, optionally split content into `references/<topic>.md`, and ship a thin `commands/<name>.md` that triggers the skill.
2. Update any `${CLAUDE_PLUGIN_ROOT}` references — these still expand the same way in commands; in the new SKILL.md body they don't expand (use `bin/` wrappers instead).
3. Ensure your `plugin.json` `commands` and `skills` paths cover both directories during the transition (or use the implicit defaults).

The official `plugin-dev` plugin's `command-development` skill is annotated as legacy for this reason.

## 2. `.claude/<plugin-name>.local.md` — per-project plugin settings

### What it is

Older pattern for per-project plugin configuration: a YAML-frontmatter + markdown file at `.claude/<plugin-name>.local.md`, gitignored, read by the plugin's hooks/commands/agents at runtime:

```markdown
---
api_endpoint: https://internal.example.com
team_slack_channel: "#deploys"
---

# Project notes for my-plugin

Free-form prose state Claude reads before invoking the plugin.
```

The plugin's hooks/commands/agents read the file and use the frontmatter values.

### What replaced it

`userConfig` in `plugin.json`. When the plugin enables, Claude Code prompts the user for the values and stores them in:

- `pluginConfigs[<plugin-id>].options` in `settings.json` (non-sensitive)
- The OS keychain (sensitive — `sensitive: true` flag)

Values substitute as `${user_config.KEY}` in MCP/LSP/hook/monitor commands and skill/agent content (non-sensitive only), and are exported as `CLAUDE_PLUGIN_OPTION_<KEY>` to subprocesses.

### Why the change

| Old `.local.md` | New `userConfig` |
|---|---|
| Hand-edited markdown | UI-prompted at enable time |
| No type checking | `type: string \| number \| boolean \| directory \| file` |
| Secrets in plain text | `sensitive: true` → OS keychain |
| Plugin reads/parses the file at runtime | Runtime substitutes values inline; plugin sees the resolved value |
| No required-field enforcement | `required: true` enforced by enable flow |
| Per-project only | Works at user / project / local scope through normal settings precedence |

### Both still work

Plugins can still ship `.claude/<plugin-name>.local.md` reads. The pattern remains useful in one specific case:

**Stateful per-session data the plugin writes back at runtime.** `userConfig` is read-only after the prompt; if your plugin needs a place to *write* per-project state (a session counter, a last-deployed timestamp, a list of recently-touched files), the markdown file is still a clean storage option.

For all other configuration concerns, prefer `userConfig`.

### Migration path

1. List each frontmatter key in your existing `.local.md` template.
2. For each, decide:
   - User-supplied at enable time, never changes mid-session → `userConfig`
   - Plugin-written, mid-session state → keep in `.local.md`
3. Move the user-supplied keys to `userConfig` in `plugin.json`. Mark API tokens / secrets as `sensitive: true`.
4. Update plugin code:
   - Hooks/commands/MCP servers: replace inline-read of the markdown file with `${user_config.KEY}` substitution
   - Skill/agent content: replace markdown-file mention with `${user_config.KEY}` for non-sensitive values, or have the user supply the value via a bin wrapper for sensitive ones
5. The `.local.md` file may now be empty (or removed) for users who don't need stateful runtime data.

The official `plugin-dev` plugin's `plugin-settings` skill documents both patterns.

## When the legacy pattern is still right

| Concern | Use legacy pattern when… |
|---|---|
| Configuration | The data is mid-session state the plugin writes (e.g., a counter, cached lookup) — `userConfig` is read-only |
| Slash commands | You're maintaining an existing plugin and the migration cost outweighs the benefit |
| Both | You want free-form prose state the model can read alongside structured values — the markdown body of `.local.md` is unstructured |

For greenfield plugins, default to the modern patterns. The legacy ones are documented so the older code in the wild stays understandable, not as a recommendation.

## See also

- [`02_settings-keys.md`](./02_settings-keys.md) — `pluginConfigs` (the modern target of `.local.md` migration)
- [`03_frontmatter-flags.md`](./03_frontmatter-flags.md) — skill / command / agent frontmatter
- [`../05_plugin-anatomy/01_directory-layout.md`](../05_plugin-anatomy/01_directory-layout.md) — modern plugin folder layout
- [`../06_capabilities/`](../06_capabilities/00_index.md) — what skills and commands look like today
- Official: [Plugins reference](https://code.claude.com/docs/en/plugins-reference)
