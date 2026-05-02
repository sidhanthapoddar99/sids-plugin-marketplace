---
name: lsp-integration
description: Use when bundling a Language Server Protocol (LSP) server with a plugin via the `lspServers` manifest field or `.lsp.json`. Covers required fields (`command`, `extensionToLanguage`), all optional fields, transport modes, capability negotiation, the binary-distribution model, and the relationship to the official `*-lsp` plugins for 12 languages (`pyright-lsp`, `typescript-lsp`, etc.).
---

# LSP server integration

A plugin can bundle a Language Server Protocol (LSP) server. Claude Code uses it for **automatic diagnostics after every edit** plus go-to-definition, find-references, and hover. The official marketplace already ships LSP plugins for 12 languages; before writing your own, check whether one exists.

## Pre-built LSP plugins

`claude-plugins-official` ships LSP plugins for: `clangd-lsp`, `csharp-lsp`, `gopls-lsp`, `jdtls-lsp`, `kotlin-lsp`, `lua-lsp`, `php-lsp`, `pyright-lsp`, `ruby-lsp`, `rust-analyzer-lsp`, `swift-lsp`, `typescript-lsp`. Install one of those before authoring your own.

Press **Ctrl+O** when the "diagnostics found" indicator appears to view diagnostics inline.

## When to author your own

- The language you need isn't covered by a pre-built plugin
- You want to bundle a heavily-customized LSP setup for a private toolchain
- You need to ship plugin-specific `initializationOptions` or `settings`

## Manifest shape

Either inline in `plugin.json` under `lspServers`, or in a separate `.lsp.json` at the plugin root.

```json
{
  "lspServers": {
    "pyright": {
      "command": "pyright-langserver",
      "args": ["--stdio"],
      "extensionToLanguage": {
        ".py": "python",
        ".pyi": "python"
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

## Fields

### Required

| Field | Notes |
|---|---|
| `command` | Path to the LSP server binary or entry script. Resolves via `$PATH` if not absolute |
| `extensionToLanguage` | Object mapping file extension (with leading dot — e.g. `".py"`, `".go"`) → LSP language ID. Tells Claude Code which files this server claims |

### Optional

| Field | Notes |
|---|---|
| `args` | Args appended to `command`. Common: `["--stdio"]` for stdio transport |
| `transport` | `"stdio"` (default), or others if the server supports them |
| `env` | Env-var overrides for the server process |
| `initializationOptions` | Object passed in the LSP `initialize` request's `initializationOptions` |
| `settings` | Object passed via `workspace/didChangeConfiguration` after init |
| `workspaceFolder` | Override for what Claude Code reports as the workspace folder. Defaults to the project root |
| `startupTimeout` | Milliseconds to wait for the server to respond to `initialize`. Default is server-class sensible |
| `shutdownTimeout` | Milliseconds to wait for graceful shutdown before SIGKILL |
| `restartOnCrash` | Boolean. Whether Claude Code restarts the server on crash |
| `maxRestarts` | If `restartOnCrash: true`, cap on restart attempts before giving up |

## Binary distribution

The language server binary itself must be installed somewhere accessible. Three patterns:

### 1. Require a system install

```json
{
  "command": "pyright-langserver",
  "args": ["--stdio"]
}
```

`command` is just a name; Claude Code resolves via `$PATH`. Document the install requirement in the plugin's README.

### 2. Bundle the binary

```
my-lsp-plugin/
├── .claude-plugin/plugin.json
└── vendor/
    └── server/
        ├── server.js
        └── ...
```

```json
{
  "command": "${CLAUDE_PLUGIN_ROOT}/vendor/server/server.js",
  "args": ["--stdio"]
}
```

Largest install footprint, smallest setup friction for users.

### 3. Fetch on first use

Use a SessionStart hook to fetch the binary into `${CLAUDE_PLUGIN_DATA}` if it's not there yet:

```bash
# hooks/session-start.sh
SERVER="$CLAUDE_PLUGIN_DATA/server"
if [[ ! -f "$SERVER" ]]; then
  curl -L -o "$SERVER" "https://example.com/server-v1.2.3"
  chmod +x "$SERVER"
fi
```

```json
{
  "command": "${CLAUDE_PLUGIN_DATA}/server",
  "args": ["--stdio"]
}
```

Smaller plugin, bigger first-run cost.

## Lifecycle

- **Started** lazily on first edit/read of a file matching `extensionToLanguage`. Multiple files in the same workspace share one server instance.
- **Restarted** if `restartOnCrash: true`, up to `maxRestarts`. Then disabled with an error.
- **Killed** on session end, plugin disable/uninstall, or `shutdownTimeout` expiration.

LSP servers do **not** hot-swap on plugin code change. `/reload-plugins` does pick up some LSP config changes (per the docs), but a full restart is the safe default for any meaningful change.

## Capability negotiation

Some LSP features require specific server capabilities (e.g. `textDocument/codeAction`). Claude Code reads the server's `initialize` response and routes only to capabilities the server advertises. If a server claims a capability but doesn't actually implement it, errors surface in the session log.

## Common pitfalls

- **Wrong field names.** `extensionToLanguage` is the field — not `filePatterns`, not `rootMarkers`. Glob patterns aren't the API; extension-to-language ID is.
- **Wrong workspace folder.** If the server's symbol resolution is off, check `workspaceFolder` and confirm the project root is what you expect.
- **Server crashes silently on init.** Capture stderr by wrapping the command:

  ```json
  {
    "command": "${CLAUDE_PLUGIN_ROOT}/wrapper.sh",
    "args": ["--server", "${CLAUDE_PLUGIN_ROOT}/vendor/server"]
  }
  ```

  Where `wrapper.sh` redirects stderr into `${CLAUDE_PLUGIN_DATA}/server.log`.

- **Version mismatch with Claude Code.** If your bundled server expects newer LSP protocol than Claude Code supports (or vice versa), pin the server version explicitly.

## Reference

- Official: [LSP servers](https://code.claude.com/docs/en/plugins-reference#lsp-servers) (ground truth)
- Official: [Code intelligence (pre-built LSPs)](https://code.claude.com/docs/en/discover-plugins#code-intelligence)
