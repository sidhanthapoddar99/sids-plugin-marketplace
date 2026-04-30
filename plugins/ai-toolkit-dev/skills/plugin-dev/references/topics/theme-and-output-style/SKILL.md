---
name: theme-and-output-style
description: Use when authoring `themes` (editor / terminal color schemes) or `outputStyles` (rendering modes for the `claude` CLI's output — tone, verbosity, formatting). Covers manifest declaration, theme schema (foreground / background / syntax tokens), output-style frontmatter (description, instructions, when-to-trigger), how users select between bundled options, and the difference between the two.
---

# Themes and output styles

Two related but distinct manifest fields. **`themes`** controls *visual* appearance; **`outputStyles`** controls *how the model is asked to write*. Both are user-selectable via `/theme` and `/output-style`.

## `themes`

A theme is a color scheme applied to Claude Code's TUI / terminal output. Plugins can ship multiple.

### Manifest shape

```json
{
  "name": "my-themes",
  "themes": {
    "midnight": {
      "displayName": "Midnight",
      "description": "Dark theme inspired by city skylines at night",
      "definition": "${CLAUDE_PLUGIN_ROOT}/themes/midnight.json"
    },
    "dawn": {
      "displayName": "Dawn",
      "description": "Light theme for daytime use",
      "definition": "${CLAUDE_PLUGIN_ROOT}/themes/dawn.json"
    }
  }
}
```

### Theme definition file

```json
{
  "name": "midnight",
  "type": "dark",
  "colors": {
    "background": "#0d1117",
    "foreground": "#c9d1d9",
    "selection": "#264f78",
    "cursor": "#79c0ff",
    "accent": "#58a6ff"
  },
  "syntax": {
    "comment": { "fg": "#8b949e", "italic": true },
    "string": { "fg": "#a5d6ff" },
    "keyword": { "fg": "#ff7b72", "bold": true },
    "function": { "fg": "#d2a8ff" },
    "number": { "fg": "#79c0ff" },
    "type": { "fg": "#ffa657" },
    "variable": { "fg": "#c9d1d9" },
    "operator": { "fg": "#ff7b72" },
    "constant": { "fg": "#79c0ff" }
  },
  "ui": {
    "border": "#30363d",
    "highlight": "#1f6feb",
    "muted": "#6e7681",
    "warning": "#d29922",
    "error": "#f85149"
  }
}
```

| Section | Purpose |
|---|---|
| `colors` | Top-level color palette |
| `syntax` | Per-token styling for code blocks. Supports `fg`, `bg`, `bold`, `italic`, `underline` |
| `ui` | Decorations: borders, highlights, error/warning colors |

`type: "dark"` or `"light"` is metadata Claude Code uses for fallback logic if a token isn't styled.

### Activation

Users select via `/theme <plugin>:<theme-name>`. Claude Code persists the choice per-scope.

## `outputStyles`

An output style is a *prompting policy* for how the model should respond. Use cases:
- Concise mode — terse responses, no narration
- Tutorial mode — explain steps verbosely as you go
- Roleplay personas — "respond as a senior engineer doing code review"

### Manifest shape

```json
{
  "outputStyles": {
    "concise": {
      "displayName": "Concise",
      "description": "Direct, minimal-prose responses",
      "definition": "${CLAUDE_PLUGIN_ROOT}/output-styles/concise.md"
    },
    "tutorial": {
      "displayName": "Tutorial",
      "description": "Walk through steps and explain reasoning",
      "definition": "${CLAUDE_PLUGIN_ROOT}/output-styles/tutorial.md"
    }
  }
}
```

### Definition file (Markdown with frontmatter)

```markdown
---
name: concise
description: Direct, minimal-prose responses
---

# Concise output style

You are operating in concise mode. Apply these rules to every response:

- No preamble, no recap of the user's question
- Use bullet points over prose where possible
- Skip code comments unless they're load-bearing
- One-line summary at the end of long responses

When the user asks a question, give the answer first; supporting reasoning second; alternatives last.
```

The body is appended to Claude Code's system prompt when the style is active. Treat it like CLAUDE.md content — actionable rules the model will internalize.

### Activation

Users select via `/output-style <plugin>:<style-name>`. Active style affects every prompt until changed.

### Default styles

Claude Code ships a default style. Plugin output styles override it when selected. Resetting to default: `/output-style default`.

## When to use which

| Want to change… | Use |
|---|---|
| Colors, syntax highlighting | `themes` |
| Tone, verbosity, response shape | `outputStyles` |
| What the model can do | A skill or agent (not these) |
| When the model proactively does something | Hooks or proactive agents |

## Combining

Themes and output styles are independent — users can mix any theme with any output style. A plugin shipping both should keep them in separate folders:

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

- **Themes too low-contrast.** Test on multiple terminals; what looks elegant on iTerm may be unreadable on plain xterm.
- **Output styles too prescriptive.** A 500-word style description is in *every* prompt — that's expensive. Aim for under 100 words of concrete rules.
- **Output styles over-specifying format.** Telling Claude to "always use exactly 3 bullet points" leads to weird outputs when 3 isn't natural. Specify shape only when it genuinely matters.
- **Themes + output style with same `name`.** They're separate namespaces, but a plugin shipping both with overlapping names confuses users. Use distinct names.

## Testing locally

```bash
claude --plugin-dir ./my-plugin
> /theme my-plugin:midnight
> /output-style my-plugin:concise

# Then run any prompt and verify the visual + tone changes
```
