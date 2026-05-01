---
title: MCP servers
description: External processes exposing tools — transports, tool naming, lifecycle, multi-plugin merging, and `/mcp`
---

# MCP servers

A **Model Context Protocol (MCP) server** is a separate process exposing tools, resources, and prompts the model can invoke. Plugins bundle MCP servers to add new capabilities — database access, browser automation, custom APIs, hosted services.

## Where it lives

Two equivalent declaration formats:

```
my-plugin/
├── .mcp.json                  # method 1 — dedicated file
├── .claude-plugin/plugin.json # method 2 — inline `mcpServers` field
└── servers/
    └── my-server.js
```

### Method 1 — `.mcp.json` (recommended for multi-server)

```json
{
  "mcpServers": {
    "database-tools": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
      "env": { "DB_URL": "${DB_URL}" }
    }
  }
}
```

### Method 2 — inline in `plugin.json`

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "mcpServers": {
    "plugin-api": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/api-server",
      "args": ["--port", "8080"]
    }
  }
}
```

## Transports

| Transport | `type` | Best for | Auth |
|---|---|---|---|
| **stdio** | (default) | Local custom servers, NPM-packaged servers | Env vars |
| **SSE** | `"sse"` | Hosted services with OAuth | OAuth (auto) |
| **HTTP** | `"http"` | REST APIs, token auth | Headers |
| **WebSocket** | `"ws"` | Real-time streaming | Headers |

### stdio

```json
{
  "filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/allowed/path"],
    "env": { "LOG_LEVEL": "debug" }
  }
}
```

### SSE

```json
{
  "asana": {
    "type": "sse",
    "url": "https://mcp.asana.com/sse"
  }
}
```

### HTTP

```json
{
  "api-service": {
    "type": "http",
    "url": "https://api.example.com/mcp",
    "headers": { "Authorization": "Bearer ${API_TOKEN}" }
  }
}
```

### WebSocket

```json
{
  "realtime-service": {
    "type": "ws",
    "url": "wss://mcp.example.com/ws",
    "headers": { "Authorization": "Bearer ${TOKEN}" }
  }
}
```

## Tool naming

When a server exposes a tool, the runtime namespaces it:

`mcp__plugin_<plugin-name>_<server-name>__<tool-name>`

Example:

| Layer | Value |
|---|---|
| Plugin | `asana` |
| Server | `asana` |
| Tool | `create_task` |
| Full name | `mcp__plugin_asana_asana__asana_create_task` |

## Pre-allowing tools in commands

Slash commands can pre-allow specific MCP tools so the user isn't prompted:

```markdown
---
allowed-tools: [
  "mcp__plugin_asana_asana__asana_create_task",
  "mcp__plugin_asana_asana__asana_search_tasks"
]
---
```

Use specific tool names rather than wildcards (`mcp__plugin_asana_asana__*`) for least-privilege.

## Environment variable expansion

All MCP configs support substitution:

| Form | Resolves to |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin install root (use for paths) |
| `${MY_VAR}` | User shell env var |
| `${user_config.<key>}` | Value from `userConfig` |

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | MCP config registered |
| Session start | stdio servers spawned; SSE/HTTP/WS connections established lazily on first tool call |
| Tool call | Connection opened if not already; tool dispatched |
| Plugin disabled | Server killed; tools removed on next session |
| Session end | All servers killed (SIGTERM, then SIGKILL) |
| Config edit | **Restart required** — running servers don't pick up changes |
| `/reload-plugins` | Picks up MCP config changes per docs, but a full restart is the safe default |

## Multi-plugin merging — name collisions

Multiple plugins can declare MCP servers. Server names are namespaced **per plugin** (the full tool name includes the plugin), so two plugins shipping a server named `database` don't collide on the wire — they appear as `mcp__plugin_p1_database__*` and `mcp__plugin_p2_database__*` distinctly.

What *can* collide: tool names that the model picks up by short reference. Always reference MCP tools by their full namespaced name.

See [`../07_lifecycle-and-runtime/07_multi-plugin-merging.md`](../07_lifecycle-and-runtime/07_multi-plugin-merging.md).

## Built-in slash commands

| Command | Use |
|---|---|
| `/mcp` | List all active MCP servers including plugin-provided. Verifies a server connected after install |

## Boundaries

An MCP server can:

- Expose any number of tools, prompts, resources via the protocol
- Maintain persistent connections to external services
- Read/write to any path the host process can access
- Initiate OAuth flows (SSE)

An MCP server **cannot**:

- See the model's conversation history (only the tool-call payloads it receives)
- Inject content outside its tool-response shape
- Override Claude Code's permission system (the user still confirms tool calls)

## Trust class

**Unsandboxed.** stdio servers run as child processes at the user's shell privilege. SSE/HTTP/WS connections speak directly to remote endpoints. Only enable MCP-bearing plugins from trusted sources.

## Security best practices

- HTTPS/WSS only — never plain `http://` or `ws://`
- Tokens via env vars or `userConfig` with `sensitive: true`, never hardcoded in the manifest
- Pre-allow specific tools in commands, not wildcards
- Document required env vars in the plugin README

## When to use MCP vs alternatives

| Goal | Use |
|---|---|
| Add new tools the model can call (DB, browser, custom API) | MCP server |
| Inject behaviour without adding tools | [Hook](./04_hooks.md) |
| Code intelligence for a language | [LSP server](./06_lsp-servers.md) |
| Bridge an external messaging surface into the conversation | [Channel](./08_channels.md) (which binds to an MCP server) |

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/mcp-integration/`
- [Channels](./08_channels.md) — channels are MCP servers with conversation-injection privileges
- [`../07_lifecycle-and-runtime/07_multi-plugin-merging.md`](../07_lifecycle-and-runtime/07_multi-plugin-merging.md)
- Official: [MCP docs](https://modelcontextprotocol.io/)
- [Capabilities index](./00_index.md)
