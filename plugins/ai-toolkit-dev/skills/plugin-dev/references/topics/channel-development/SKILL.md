---
name: channel-development
description: Use when authoring `channels` — the plugin manifest field that binds an MCP server to an external messaging surface (Slack, Discord, Telegram) so the model can send and receive messages there. Covers the `channels` array shape, the required `server` field that points at a key in the plugin's `mcpServers`, per-channel `userConfig` for bot tokens / owner IDs, and how messages are injected into the conversation.
---

# Authoring channels

A **channel** binds one of the plugin's MCP servers to an external messaging surface (Slack, Discord, Telegram, etc.). Messages received on that surface get **injected into the Claude Code conversation**; the model can reply through the same MCP server. This is how plugins like the official `slack-channel`, `discord-channel`, and `telegram-channel` plugins work.

## Mental model

- Channels are NOT notification handlers — they're full bidirectional conversation surfaces.
- Each channel is backed by an **MCP server** the plugin already declares in `mcpServers` (or `.mcp.json`). The MCP server speaks the messaging protocol (Slack API, etc.); the channel binding tells Claude Code "treat this MCP server as a chat surface".
- Multiple channels of different types can coexist in one plugin.

## Manifest shape

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
          "description": "Only this user's DMs will be injected into the conversation",
          "required": true
        }
      }
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `server` | yes | Must match a key in `mcpServers` |
| `userConfig` | optional | Per-channel `userConfig` block — same shape as plugin-level `userConfig` (see [`../../config/user-config.md`](../../config/user-config.md)). Used for bot tokens, owner IDs, etc. |

## How messages flow

1. The MCP server (your code) connects to the external surface via its API.
2. When a message arrives on the surface, the MCP server forwards it to Claude Code via the channel binding. Claude Code injects it into the active conversation as a user-visible context message.
3. The model can reply by invoking the MCP server's "send message" tool. The MCP server posts to the external surface.

The MCP server is a normal Claude Code MCP server (stdio, HTTP, or SSE transport). The channel binding is what gives it conversation-injection privileges.

## When to use

- You want to use Claude Code from Slack/Discord/Telegram without leaving the chat surface
- You want a long-running session that picks up messages from an external place and routes them back
- You want a notification surface where the user can also reply and have the model respond

## When NOT to use

- One-shot alerts to an external service → use a hook with a webhook script (write a hook script that POSTs to the webhook on `Notification` events)
- Sending Claude Code's session output to a log → the MCP server itself can implement that without a `channels` binding
- Internal plugin events (task done, hook fired) for which you want a flexible delivery target → still a hook, not a channel

## What the per-channel `userConfig` is for

Each channel binding can declare its own `userConfig` block — typically for:

- The bot's auth token (`sensitive: true`)
- An owner user ID (so DMs from random users aren't injected)
- A workspace / server / channel ID restricting where messages flow

Values flow into the bound MCP server via `${user_config.<key>}` substitution and `CLAUDE_PLUGIN_OPTION_<KEY>` env vars (see [`../../config/user-config.md`](../../config/user-config.md)).

## Multiple channels

A plugin can ship multiple channels — e.g. a Slack channel and a Telegram channel both backed by their own MCP servers:

```json
{
  "channels": [
    { "server": "slack-bot", "userConfig": { ... } },
    { "server": "telegram-bot", "userConfig": { ... } }
  ]
}
```

Each binds independently. The user can enable/disable each via `/plugin`.

## Common pitfalls

- **Forgetting to declare the MCP server.** `server` must match an existing `mcpServers` key. Claude Code rejects the plugin at load if the binding's server doesn't exist.
- **Putting auth in `mcpServers.env` directly.** Hardcoding tokens in the manifest means they ship with the plugin. Use `userConfig` with `sensitive: true` and reference the value via `${user_config.<key>}`.
- **No owner restriction.** Without `ownerUserId` (or equivalent), any message on the surface is injected — if the surface is shared (a public Slack channel), the conversation will fill up fast. Always restrict.

## Reference

- Docs: `docs/Claude Plugins/07_reference.md` § Channels (ground truth)
- Official: [Channels](https://code.claude.com/docs/en/plugins-reference#channels)
- Look at an existing channel plugin (e.g. the `slack-channel` plugin in `claude-plugins-official`) for a worked example of the MCP server + channel binding pair.
