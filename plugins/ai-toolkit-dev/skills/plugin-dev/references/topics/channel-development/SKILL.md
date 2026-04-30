---
name: channel-development
description: Use when authoring `channels` — the plugin manifest field for declaring notification routing surfaces. Covers what a channel is (a destination Claude Code can route notifications to — Slack, email, OS notification, MCP-server-mediated), the manifest declaration, the channel handler interface, when to use a channel vs a hook vs a bin, and patterns for selective routing based on event type or user-set preferences.
---

# Authoring channels

A **channel** is a destination for notifications. When Claude Code wants to surface an event to the user (a long task completed, a hook fired, a model response is ready), it routes the notification through one or more channels. Plugins extend the available channels.

## When to use

- You want Claude Code's notifications to reach an external surface (Slack, email, push notification, OS notification)
- You want to filter or transform notifications before they're sent
- You want a structured I/O channel between the user and the session that's separate from the main chat

When NOT to use:
- One-shot user-facing alerts → a `Notification` hook may be enough
- Real-time bidirectional communication during a session → MCP server is the right surface

## Manifest shape

```json
{
  "name": "my-plugin",
  "channels": {
    "slack-team": {
      "displayName": "Slack — team-alerts",
      "description": "Posts to the team-alerts channel via webhook",
      "handler": "${CLAUDE_PLUGIN_ROOT}/channels/slack.sh",
      "events": ["task-complete", "hook-failure"],
      "default": false
    },
    "desktop": {
      "displayName": "Desktop notification",
      "handler": "${CLAUDE_PLUGIN_ROOT}/channels/desktop.sh",
      "events": ["*"],
      "default": true
    }
  }
}
```

| Field | Purpose |
|---|---|
| `displayName` | What appears in `/notify` UI |
| `description` | Help text in `/notify` UI |
| `handler` | Script invoked per notification (see "Handler interface" below) |
| `events` | Event types this channel subscribes to. `["*"]` = all events |
| `default` | Whether to enable by default (user can toggle) |
| `userConfig` | Optional schema for channel-specific settings (e.g. webhook URL) |

## Handler interface

Each notification invokes the handler with a JSON envelope on stdin:

```json
{
  "channel": "slack-team",
  "event": "task-complete",
  "title": "Long task finished",
  "body": "The build completed successfully in 2m14s",
  "severity": "info",
  "session_id": "abc123",
  "timestamp": "2026-05-01T12:34:56Z",
  "metadata": {
    "task": "build-frontend",
    "duration_ms": 134000
  }
}
```

The handler reads, processes, and exits. Exit code:
- `0` — delivered successfully
- non-zero — delivery failed; Claude Code logs and may retry per `retryPolicy` (see below)

### Slack webhook example

```bash
#!/usr/bin/env bash
# channels/slack.sh
set -euo pipefail

webhook=$(jq -r .slackWebhookUrl "$CLAUDE_PLUGIN_CONFIG")
event=$(jq -r '. | .event + ": " + .title' /dev/stdin | cat -)

# Re-read stdin (already consumed by jq above) — fix by buffering
payload=$(cat)
title=$(echo "$payload" | jq -r .title)
body=$(echo "$payload" | jq -r .body)
severity=$(echo "$payload" | jq -r .severity)

curl -X POST "$webhook" \
  -H 'Content-Type: application/json' \
  -d "{\"text\": \"*$title*\\n$body\", \"username\": \"Claude Code\"}" \
  >/dev/null
```

### OS notification example (macOS)

```bash
#!/usr/bin/env bash
payload=$(cat)
title=$(echo "$payload" | jq -r .title)
body=$(echo "$payload" | jq -r .body)
osascript -e "display notification \"$body\" with title \"$title\""
```

## Event types

Standard events Claude Code emits:

| Event | When |
|---|---|
| `task-complete` | A long-running task (>30s) finished |
| `tool-error` | A tool invocation failed |
| `hook-failure` | A hook script returned non-zero |
| `agent-done` | A subagent finished and returned to the parent |
| `session-end` | The session is ending |
| `user-attention-required` | The model determined the user needs to step in |

Plugins can also emit custom events from hooks or bins:

```bash
claude notify --event "deploy-complete" --title "..." --body "..."
```

## Retry policy

Default: failed deliveries retry once after 5s, then drop with a logged error. Override:

```json
{
  "channels": {
    "slack-team": {
      ...,
      "retryPolicy": {
        "attempts": 5,
        "backoff": "exponential",
        "initial_ms": 1000,
        "max_ms": 30000
      }
    }
  }
}
```

For idempotent destinations (Slack, email), retries are safe. For destinations that might double-deliver, use `attempts: 1`.

## User-configurable channels

Most channels need user-specific config (webhook URL, email address, etc.). Use `userConfig`:

```json
{
  "channels": {
    "slack-team": {
      ...,
      "userConfig": {
        "type": "object",
        "properties": {
          "slackWebhookUrl": {
            "type": "string",
            "format": "uri",
            "description": "Incoming webhook URL for the target channel"
          }
        },
        "required": ["slackWebhookUrl"]
      }
    }
  }
}
```

Resolved values are passed to the handler via `${CLAUDE_PLUGIN_CONFIG}` (same as plugin-level `userConfig`, but scoped to this channel).

## Filtering events

Per-channel `events` filter is the coarse control. For finer filtering inside the handler:

```bash
event=$(jq -r .event /dev/stdin)
if [[ "$event" == "tool-error" && "$(jq -r '.metadata.tool' /dev/stdin)" == "Bash" ]]; then
  # only Bash errors are interesting for this channel
  send_notification
fi
```

## Channel UI

Users manage channels via `/notify`:

- `/notify list` — show all available channels and their enabled state
- `/notify enable <plugin>:<channel>`
- `/notify disable <plugin>:<channel>`
- `/notify test <plugin>:<channel>` — fires a test notification

Per-scope settings persist enable state.

## Common pitfalls

- **Handler is slow.** Notifications are sent inline; a slow handler delays the next user prompt. Spawn an async background process if delivery takes >100ms:
  ```bash
  ( do-the-actual-send ) >/dev/null 2>&1 &
  exit 0
  ```
- **Handler reads stdin twice.** Once you've piped stdin to `jq`, it's gone. Buffer with `payload=$(cat)` first.
- **Webhooks in plugin code.** Don't hardcode webhook URLs in scripts — use `userConfig` so users supply their own.
- **Noisy default-on channels.** A channel with `default: true` and `events: ["*"]` will spam every user who installs the plugin. Default to `false` or `events: ["user-attention-required"]` (the most selective event).

## Testing

```bash
claude --plugin-dir ./my-plugin
> /notify enable my-plugin:desktop
> /notify test my-plugin:desktop

# In a real run, trigger a long task and verify the channel fires
```
