---
title: Themes
description: Color schemes shipped via JSON files — base preset, sparse overrides, /theme activation, the Ctrl+E copy-for-edit pattern
---

# Themes

A **theme** is a JSON file declaring a color scheme. Plugin-shipped themes appear in the `/theme` picker alongside built-in presets and the user's local themes. Each theme starts from a built-in **base preset** and applies a sparse map of color **overrides**.

## Where it lives

```
my-plugin/
├── .claude-plugin/plugin.json
└── themes/
    ├── midnight.json
    └── dawn.json
```

Default scan: `themes/*.json`. Override via `"themes"` in `plugin.json` (path-replacement field — include `"./themes/"` if you want to keep the default scan and add more).

## Schema — theme file

```json
{
  "name": "midnight",
  "base": "dark",
  "overrides": {
    "comment": "#8b949e",
    "string": "#a5d6ff",
    "keyword": "#ff7b72",
    "function": "#d2a8ff"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Theme identifier shown in `/theme` |
| `base` | yes | A built-in preset name. Tokens you don't override come from this base |
| `overrides` | yes (may be empty) | Sparse map of color tokens → hex / named color. Only customized tokens appear |

There is **no** nested `colors` / `syntax` / `ui` structure, **no** per-token `bold`/`italic`/`underline` flags, **no** `displayName`/`description`/`definition` indirection. The shape above is the full vocabulary.

## Activation

Users select via the `/theme` slash command. Plugin-shipped themes appear inline with built-in presets and `~/.claude/themes/` user themes.

When a plugin theme is selected, it persists in the user's config as:

```
custom:<plugin-name>:<theme-slug>
```

## Editing a plugin theme — the Ctrl+E pattern

Plugin themes are **read-only** in `/theme` — the plugin's authoritative version stays clean across updates. To customize:

1. Highlight a plugin theme in the `/theme` picker
2. Press **Ctrl+E**
3. Claude Code copies the JSON into `~/.claude/themes/`
4. The user edits the copy freely

This way the plugin's version doesn't drift, and the user owns their copy.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Theme(s) registered in next session's `/theme` listing |
| Session start | All plugin themes scanned, indexed |
| `/theme` selection | Active theme switches; persists in user config |
| `/reload-plugins` | Hot-swap: theme JSON edits picked up without restart |
| Plugin disabled | Themes removed from picker on next session |

Hot-swappable. No restart required.

## Boundaries

A theme can:

- Override any color token the base preset defines
- Inherit unmodified tokens from the base
- Coexist with arbitrary numbers of other plugin and user themes

A theme **cannot**:

- Add new color tokens not in the base preset
- Set per-token text decoration (bold, italic, underline)
- Affect anything other than terminal colors (no font, layout, spacing)

## Trust class

**UI only.** Themes are pure data the renderer reads. No code execution. Safe to install from untrusted sources purely on this surface (though the rest of the plugin still applies the normal trust model).

## When to ship a theme vs alternatives

| Goal | Use |
|---|---|
| Change colors / syntax highlighting | Theme |
| Change response shape, verbosity, tone | [Output style](./10_output-styles.md) |
| Change what the model can do | [Skill](./01_skills.md) or [agent](./03_subagents.md) |

## Common pitfalls

- **Inventing nested structure.** Don't ship `themes/<name>.json` with `colors`/`syntax`/`ui` sub-objects — Claude Code doesn't read that shape. Stick to `name` / `base` / `overrides`
- **Missing `base`.** Without a base preset, the theme has nothing to inherit from and the picker rejects it
- **Path-replacement gotcha.** Setting `"themes"` in `plugin.json` to a custom path **replaces** the default `themes/*.json` scan. Include both paths if you want to keep the default

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/theme-and-output-style/`
- [Output styles](./10_output-styles.md) — the related but distinct response-shape surface
- Official: [Themes](https://code.claude.com/docs/en/plugins-reference#themes) — ground-truth schema
- [Capabilities index](./00_index.md)
