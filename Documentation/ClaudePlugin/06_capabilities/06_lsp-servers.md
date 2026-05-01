---
title: LSP servers
description: Language Server Protocol integration — required and optional fields, capability negotiation, the bundle-vs-system-install distinction, pre-built LSP plugins
---

# LSP servers

A **Language Server Protocol (LSP) server** gives Claude Code automatic diagnostics after every edit, plus go-to-definition, find-references, and hover. Plugins bundle LSP configuration for languages where a server binary exists.

## Where it lives

Two equivalent declaration formats:

```
my-lsp-plugin/
├── .lsp.json                  # method 1 — dedicated file
└── .claude-plugin/plugin.json # method 2 — inline `lspServers` field
```

### Either format

```json
{
  "lspServers": {
    "pyright": {
      "command": "pyright-langserver",
      "args": ["--stdio"],
      "extensionToLanguage": {
        "py": "python",
        "pyi": "python"
      },
      "settings": {
        "python": {
          "analysis": { "typeCheckingMode": "basic" }
        }
      }
    }
  }
}
```

## Schema — fields

### Required

| Field | Notes |
|---|---|
| `command` | Path to the LSP server binary or entry script. Resolves via `$PATH` if not absolute |
| `extensionToLanguage` | Object mapping file extension (no leading dot) → LSP language ID. Tells Claude Code which files this server claims |

### Optional

| Field | Notes |
|---|---|
| `args` | Args appended to `command`. Common: `["--stdio"]` |
| `transport` | `"stdio"` (default), or others if the server supports them |
| `env` | Env-var overrides for the server process |
| `initializationOptions` | Object passed in the LSP `initialize` request's `initializationOptions` |
| `settings` | Object passed via `workspace/didChangeConfiguration` after init |
| `workspaceFolder` | Override for the workspace folder reported to the server. Defaults to the project root |
| `startupTimeout` | Milliseconds to wait for `initialize` response |
| `shutdownTimeout` | Milliseconds to wait for graceful shutdown before SIGKILL |
| `restartOnCrash` | Boolean — restart the server on crash |
| `maxRestarts` | Cap on restart attempts (used with `restartOnCrash: true`) |

The field is `extensionToLanguage` — **not** `filePatterns`, **not** `rootMarkers`. Glob patterns aren't part of the API; extension-to-language ID is.

## Pre-built LSP plugins

`claude-plugins-official` already ships LSP plugins for 11 languages. Install one of these before authoring your own:

| Plugin | Language |
|---|---|
| `clangd-lsp` | C / C++ |
| `csharp-lsp` | C# |
| `gopls-lsp` | Go |
| `jdtls-lsp` | Java |
| `kotlin-lsp` | Kotlin |
| `lua-lsp` | Lua |
| `php-lsp` | PHP |
| `pyright-lsp` | Python |
| `rust-analyzer-lsp` | Rust |
| `swift-lsp` | Swift |
| `typescript-lsp` | TypeScript |

Press **Ctrl+O** when the "diagnostics found" indicator appears in the UI to view diagnostics inline.

## When to author your own

- The language isn't covered by a pre-built plugin
- You're bundling a heavily-customized LSP setup for a private toolchain
- You need plugin-specific `initializationOptions` or `settings`

## Binary distribution patterns

The language-server binary itself must be reachable. Three approaches:

### 1. Require a system install

```json
{ "command": "pyright-langserver", "args": ["--stdio"] }
```

`command` is a name; Claude Code resolves via `$PATH`. Document the install requirement in the plugin README.

### 2. Bundle the binary

```
my-lsp-plugin/
├── .claude-plugin/plugin.json
└── vendor/server/server.js
```

```json
{
  "command": "${CLAUDE_PLUGIN_ROOT}/vendor/server/server.js",
  "args": ["--stdio"]
}
```

Largest install footprint, smallest setup friction.

### 3. Fetch on first use

A `SessionStart` hook downloads the binary into `${CLAUDE_PLUGIN_DATA}` if missing:

```bash
SERVER="$CLAUDE_PLUGIN_DATA/server"
if [[ ! -f "$SERVER" ]]; then
  curl -L -o "$SERVER" "https://example.com/server-v1.2.3"
  chmod +x "$SERVER"
fi
```

Smaller plugin, bigger first-run cost.

## Capability negotiation

LSP servers advertise capabilities via the `initialize` response (`textDocument/codeAction`, `textDocument/hover`, etc.). Claude Code routes only to capabilities the server claims. Servers that claim a capability they don't actually implement surface errors in the session log.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Config registered |
| Session start | Server **not yet started** |
| First file matching `extensionToLanguage` opened | Server spawned; multiple matching files in same workspace share one instance |
| Server crash + `restartOnCrash: true` | Restarted up to `maxRestarts` times |
| Plugin disabled / session end / `shutdownTimeout` elapsed | Server killed |
| Config edit | Full restart for safe behaviour. `/reload-plugins` picks up some changes per docs |

Servers are spawned **lazily** on first file match — not at session start.

## Boundaries

An LSP server can:

- Provide diagnostics, definitions, references, hover, code actions, symbols, etc. — anything LSP exposes
- Run any local analysis the server's design supports

An LSP server **cannot**:

- Execute arbitrary tool calls — only the capabilities LSP defines flow through
- Inject content into the model's prompt directly (diagnostics are surfaced via the editor pane, accessed via Ctrl+O)

## Trust class

**Unsandboxed.** LSP servers run as child processes at the user's shell privilege. The server binary itself is whatever the plugin author shipped or pointed at — install with the same trust posture as MCP servers.

## Common pitfalls

- **Wrong field names.** `extensionToLanguage` is the field — not `filePatterns`/`rootMarkers`
- **Wrong workspace folder.** If symbol resolution is off, check `workspaceFolder`
- **Server crashes silently on init.** Wrap `command` in a script that captures stderr to `${CLAUDE_PLUGIN_DATA}/server.log`
- **Protocol version mismatch.** Pin the server version explicitly when bundling

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/lsp-integration/`
- [Reference](../../../docs/Claude%20Plugins/07_reference.md) § LSP servers — ground-truth schema
- Official: [LSP servers](https://code.claude.com/docs/en/plugins-reference#lsp-servers)
- Official: [Code intelligence (pre-built)](https://code.claude.com/docs/en/discover-plugins#code-intelligence)
- [Capabilities index](./00_index.md)
