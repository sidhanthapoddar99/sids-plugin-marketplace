---
name: theme-and-output-style
description: Use when authoring `themes` (color schemes shipped via `themes/<name>.json` with a `base` preset and a sparse `overrides` map) or `outputStyles` (response-formatting styles configured via `outputStyles` in `plugin.json`). Covers both schemas, how users select between bundled options (`/theme`, **Ctrl+E** to copy for editing), and what the official marketplace ships for reference (`explanatory-output-style`, `learning-output-style`).
---

# Themes and output styles

Two related but distinct manifest fields. **`themes`** controls visual color schemes; **`outputStyles`** controls how Claude formats responses. Both are user-selectable.

## Themes

A theme is a JSON file at `themes/<name>.json` (or any path declared in `themes` in `plugin.json`). Each theme starts from a built-in **base preset** and applies a sparse map of color **overrides**.

### Theme file shape

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

| Field | Notes |
|---|---|
| `name` | Theme identifier |
| `base` | A built-in preset name. Inherited tokens you don't override come from this base |
| `overrides` | Sparse map of color tokens → hex / named color. Only the tokens you customize need to appear |

There is no nested `colors`/`syntax`/`ui` object structure, no per-token `bold`/`italic`/`underline` flags, no `displayName`/`description`/`definition` indirect-pointer pattern. The shape above is the full vocabulary.

### Discovery

Default scan: `themes/*.json`. Override via `"themes"` in `plugin.json` (this is a **path-replacement** field — see [`../../config/manifest.md`](../../config/manifest.md), include `./themes/` in the array if you want to keep the default scan plus add more).

### Activation

Users select via `/theme`. Plugin-shipped themes appear alongside built-in presets and the user's local themes.

When a plugin theme is selected, the choice persists as `custom:<plugin-name>:<theme-name>` in the user's config.

### Editing a plugin theme

Plugin themes are read-only in `/theme`. To customize:
- Press **Ctrl+E** on a plugin theme in the picker → Claude Code copies it into `~/.claude/themes/`
- The user can edit the copy freely

This way the plugin's authoritative version stays clean across plugin updates and the user can iterate on their copy.

## Output styles

An output style is a prompting policy that changes how Claude formats responses. Configured via `outputStyles` in `plugin.json`.

### Manifest shape

```json
{
  "outputStyles": "./output-styles/"
}
```

Or specific files:

```json
{
  "outputStyles": ["./styles/concise.md", "./styles/tutorial.md"]
}
```

The value is a path string or array of paths. Each output style is a Markdown file with frontmatter; its body is appended to Claude Code's system prompt when the style is active.

### Discovery

Default scan: `outputStyles/*.md` (or wherever the plugin places them). `outputStyles` in `plugin.json` is a path-replacement field — to keep the default plus add more, include both.

### Definition file (Markdown with frontmatter)

```markdown
---
name: concise
description: Direct, minimal-prose responses
---

You are operating in concise mode. Apply these rules:

- No preamble, no recap of the user's question
- Bullet points over prose where possible
- Skip code comments unless load-bearing
- One-line summary at the end of long responses
```

Treat the body like CLAUDE.md content — actionable rules the model internalizes.

### Activation

Users select via `/output-style`. The active style affects every prompt until changed. Plugin-shipped styles appear alongside built-in styles.

### Examples in the official marketplace

`claude-plugins-official` ships:
- `explanatory-output-style` — adds educational annotations on code
- `learning-output-style` — interactive learning-mode formatting

Read those for worked examples.

## When to use which

| Want to change… | Use |
|---|---|
| Colors, syntax highlighting | `themes` |
| Tone, verbosity, response shape | `outputStyles` |
| What the model can do | A skill or agent (not these) |

## Combining

Themes and output styles are independent — users can mix any theme with any output style. Ship them as separate files in separate directories:

```
my-plugin/
├── .claude-plugin/plugin.json
├── themes/
│   ├── midnight.json
│   └── dawn.json
└── output-styles/
    ├── concise.md
    └── tutorial.md
```

## Common pitfalls

- **Inventing nested theme structure.** Don't ship `themes/<name>.json` with `colors`/`syntax`/`ui` objects — Claude Code doesn't read that shape. Use `name` / `base` / `overrides`.
- **Over-prescribing in output styles.** A 500-word style is in *every* prompt — expensive. Aim for under 100 words of concrete rules.
- **Format-rigid output styles.** Telling Claude "always use exactly 3 bullet points" leads to weird outputs when 3 isn't natural. Specify shape only when it genuinely matters.

## Reference

- Docs: `docs/Claude Plugins/07_reference.md` § Themes and § Output styles (ground truth)
- Official: [Themes](https://code.claude.com/docs/en/plugins-reference#themes)
- Official: [Output styles](https://code.claude.com/docs/en/discover-plugins#output-styles)
