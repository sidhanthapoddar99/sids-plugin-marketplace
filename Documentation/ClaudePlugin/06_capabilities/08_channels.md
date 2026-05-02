---
title: Channels
description: Bidirectional conversation surfaces backed by an MCP server — Slack/Discord/Telegram-style messaging injected into Claude Code
---

# Channels

A **channel** binds one of the plugin's MCP servers to an external messaging surface (Slack, Discord, Telegram). Messages received on the surface get **injected into the active Claude Code conversation**; the model can reply through the same MCP server. This is how the official `slack-channel`, `discord-channel`, and `telegram-channel` plugins work.

## Mental model

- Channels are **NOT** notification handlers. They're full bidirectional conversation surfaces.
- Each channel is backed by an **MCP server** the plugin already declares in `mcpServers` (or `.mcp.json`). The MCP server speaks the messaging protocol; the channel binding tells Claude Code to treat that MCP server as a chat surface.
- Multiple channels of different types can coexist in one plugin.

## Where it lives

```
my-plugin/
├── .claude-plugin/plugin.json # `mcpServers` + `channels`
└── server/slack.js            # the MCP server implementation
```

Declared via `channels` array in `plugin.json`. Each entry binds to a key in `mcpServers`.

## Schema

```json
{
  "name": "team-slack",
  "mcpServers": {
    "slack-bot": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/server/slack.js"],
      "env": {
        "SLACK_BOT_TOKEN": "${user_config.botToken}"
      }
    }
  },
  "channels": [
    {
      "server": "slack-bot",
      "userConfig": {
        "botToken": {
          "type": "string",
          "title": "Slack bot token",
          "sensitive": true,
          "required": true
        },
        "ownerUserId": {
          "type": "string",
          "title": "Owner Slack user ID",
          "description": "Only this user's DMs will be injected",
          "required": true
        }
      }
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `server` | yes | Must match a key in `mcpServers`. Claude Code rejects the plugin at load if missing |
| `userConfig` | no | Per-channel `userConfig` block — same shape as plugin-level. Used for bot tokens, owner IDs, etc. |

## How messages flow

```
External surface (Slack)
        ↕  (MCP server speaks the protocol)
   MCP server (your code)
        ↕  (channel binding gives conversation-injection)
  Claude Code session
```

1. The MCP server (your code) connects to the external surface via its API
2. When a message arrives on the surface, the MCP server forwards it to Claude Code via the channel binding. Claude Code injects it into the active conversation as a context message
3. The model can reply by invoking the MCP server's "send message" tool. The MCP server posts back to the external surface

The MCP server is a normal Claude Code MCP server (stdio, HTTP, or SSE transport). The **channel binding** is what gives it conversation-injection privileges.

## Per-channel `userConfig`

Each channel can declare its own `userConfig` — typically for:

- The bot's auth token (`sensitive: true`, stored in OS keychain)
- An **owner user ID** (so DMs from random users aren't injected)
- A workspace / server / channel ID restricting where messages flow

Values flow into the bound MCP server via:

| Form | Where |
|---|---|
| `${user_config.<key>}` | MCP server `command` / `args` / `env` template-expansion |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | Env var available to the MCP server process |

See [`../05_plugin-anatomy/`](../05_plugin-anatomy/) and the official `userConfig` reference for the full schema.

## Multiple channels

A plugin can ship multiple channels — e.g. one Slack channel and one Telegram channel, each backed by its own MCP server:

```json
{
  "channels": [
    { "server": "slack-bot",    "userConfig": { "botToken": {...} } },
    { "server": "telegram-bot", "userConfig": { "botToken": {...} } }
  ]
}
```

Each binds independently. The user can enable/disable channels via `/plugin`.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | `userConfig` prompts shown; tokens stored in keychain |
| Session start | Bound MCP server starts; channel binding registers |
| Message arrives on surface | Injected into conversation as context |
| Model invokes "send message" tool | MCP server posts to surface |
| Plugin disabled | MCP server killed; channel binding deregistered |
| Config edit | Restart required (same as MCP servers) |

## Boundaries

A channel can:

- Inject messages from the external surface into the conversation
- Provide tools (via the bound MCP server) for sending messages back
- Restrict message flow via per-channel `userConfig` (owner ID, channel ID)

A channel **cannot**:

- Run without an MCP server backing it
- Restrict which messages the conversation injects without your MCP server filtering them first
- Bypass Claude Code's permission system on outbound tool calls

## Trust class

**Unsandboxed** (via the bound MCP server). The MCP server runs at the user's shell privilege; tokens are in the OS keychain.

## When to use a channel vs alternatives

| Goal | Use |
|---|---|
| Use Claude Code from Slack/Discord without leaving the chat | Channel |
| Long-running session that picks up external messages and routes them back | Channel |
| One-shot alert to an external service | [Hook](./04_hooks.md) (Notification event with webhook script) |
| Send Claude Code's session output to a log | The MCP server alone (no channel binding needed) |
| Internal plugin events with flexible delivery | Hook, not a channel |

## Common pitfalls

- **Forgetting to declare the MCP server.** `server` must match an existing `mcpServers` key
- **Hardcoding auth in `mcpServers.env`.** Tokens in the manifest ship with the plugin. Use `userConfig` with `sensitive: true` and reference via `${user_config.<key>}`
- **No owner restriction.** Without `ownerUserId` or equivalent, *every* message on the surface is injected — public Slack channels will overwhelm the conversation. Always restrict.

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/channel-development/`
- [MCP servers](./05_mcp-servers.md) — the underlying surface channels build on
- Official: [Channels](https://code.claude.com/docs/en/plugins-reference#channels) — ground-truth schema
- Worked example: `slack-channel` plugin in `claude-plugins-official`
- [Capabilities index](./00_index.md)
