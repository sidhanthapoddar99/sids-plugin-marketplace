---
name: lsp-integration
description: Use when bundling a Language Server Protocol server with a plugin via the `lspServers` manifest field — declaration shape, launch flags, server-specific config, file-pattern triggers, lifecycle (auto-start, restart on file change), and common pitfalls (missing binaries, version mismatches, capability negotiation).
---

# LSP server integration

A plugin can bundle a Language Server Protocol (LSP) server so Claude Code can use it for code intelligence on the file types the server supports. This is how `pyright-lsp`, `typescript-lsp`, and similar single-purpose plugins work.

## When to use

- Your plugin's value is providing better code understanding for a specific language or framework
- You can either bundle a binary, fetch one on first use, or rely on a system-installed binary

When NOT to use:
- For ephemeral analysis tasks → a bin script that runs the analyzer on demand may be enough
- For non-LSP analyzers (linters, formatters) → use bins or hooks; LSP is specifically the LSP protocol

## Manifest shape

```json
{
  "name": "pyright-lsp",
  "lspServers": {
    "pyright": {
      "command": "${CLAUDE_PLUGIN_ROOT}/vendor/pyright/index.js",
      "args": ["--stdio"],
      "filePatterns": ["*.py", "*.pyi"],
      "rootMarkers": ["pyproject.toml", "setup.py", "requirements.txt"],
      "settings": {
        "python": {
          "analysis": {
            "typeCheckingMode": "basic"
          }
        }
      }
    }
  }
}
```

| Field | Purpose |
|---|---|
| `command` | Path to the LSP server binary or entry script. Usually `${CLAUDE_PLUGIN_ROOT}/...` for bundled servers |
| `args` | Args passed to the server (typically includes `--stdio` or `--socket` to set transport) |
| `filePatterns` | Glob patterns for files this server should be activated for |
| `rootMarkers` | Files that mark a project root (the LSP server's `workspaceFolder` is set to the nearest ancestor containing one of these) |
| `settings` | Server-specific config sent in the LSP `initialize` request |
| `env` | Optional env-var overrides for the server process |
| `transport` | `"stdio"` (default), `"socket"`, or `"pipe"` |

## Bundling vs system-install

Three strategies:

### 1. Bundle the binary

Best UX (zero install steps for users) but largest plugin footprint:

```
my-lsp-plugin/
├── .claude-plugin/plugin.json
└── vendor/
    └── server/
        ├── server.js
        └── ...
```

Then `command: "${CLAUDE_PLUGIN_ROOT}/vendor/server/server.js"`.

### 2. Fetch on SessionStart

Smaller plugin, fetches the server to `${CLAUDE_PLUGIN_DATA}` on first use:

```bash
# hooks/session-start.sh
SERVER="$CLAUDE_PLUGIN_DATA/server"
if [[ ! -f "$SERVER" ]]; then
  curl -L -o "$SERVER" "https://example.com/server-v1.2.3"
  chmod +x "$SERVER"
fi
```

Then `command: "${CLAUDE_PLUGIN_DATA}/server"`.

### 3. Require system install

Smallest plugin, but the user must install the server (`npm install -g pyright`, `brew install gopls`, etc.). Document the requirement in the README.

```json
{
  "command": "pyright-langserver",
  "args": ["--stdio"]
}
```

`command` here is just a name — Claude Code resolves it via `$PATH`.

## File patterns and root markers

`filePatterns` decides *which files* the server is responsible for. Glob syntax: `*.py`, `**/*.py`, `pyproject.toml`.

`rootMarkers` decides *where* a project boundary is. When Claude Code edits `src/foo.py`, it walks up looking for the nearest dir containing `pyproject.toml` (or other markers) and tells the LSP server "this is your workspace folder". Get this wrong and the server won't see imports correctly.

For monorepos with multiple sub-projects, each sub-project should have its own marker file — the server picks them up as separate workspaces.

## Lifecycle

- **Started**: lazily on first edit/read of a matching file. Multiple files in the same workspace share one server instance
- **Restarted**: when the server crashes (auto-restart up to 3 times in 60s, then disabled with a warning), or when the user runs `/lsp restart`
- **Killed**: on session end, or when the plugin is disabled/uninstalled

LSP servers are NOT hot-swappable on plugin code change — restart `claude` to pick up server changes (see `lifecycle-and-storage.md`).

## Capability negotiation

Some LSP features require a specific server capability (e.g. `textDocument/codeAction`). Claude Code reads the server's `initialize` response and routes only to capabilities the server advertises. If a server claims a capability but doesn't actually implement it, errors surface in the session log.

## Common pitfalls

### Server not found

```
Error: lspServers.pyright: command not found
```

The `command` path doesn't exist or isn't executable. Check:
- Bundled: did you commit the binary? (LFS, gitignored, etc.)
- Fetched: did the SessionStart fetch run before LSP initialization? (race condition)
- System: is the binary on `$PATH` for the user's shell?

### Wrong workspace folder

LSP server can see files but symbol resolution is broken. Usually `rootMarkers` is missing or wrong — server thinks workspace is one level too high or too low.

### Server crashes on initialize

Server exits before responding to `initialize`. Capture stderr:

```json
{
  "command": "wrapper.sh",
  "args": ["--server", "${CLAUDE_PLUGIN_ROOT}/vendor/server"]
}
```

Where `wrapper.sh` is:

```bash
#!/usr/bin/env bash
exec "$@" 2>>"$CLAUDE_PLUGIN_DATA/server.log"
```

Then check `~/.claude/plugins/data/<plugin>/server.log` for the actual error.

### Version mismatch

Bundled server expects newer protocol than Claude Code supports, or vice versa. Check the server's release notes and the plugin's documented compatibility range. If you bundle a server that requires capabilities Claude Code doesn't support yet, either pin to an older server version or document the version requirement.

## Testing locally

```bash
claude --plugin-dir ./my-lsp-plugin

# Inside session: open a matching file
> view src/foo.py

# Run LSP-specific commands
> /lsp status               # which servers are running
> /lsp restart pyright      # restart a server manually
```

For automated testing of LSP behavior, run a representative prompt that requires LSP-served code intelligence and check the response.
