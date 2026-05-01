# `disable-model-invocation`

A boolean frontmatter flag on a skill or slash command. When set to `true`, the model cannot auto-invoke the skill or command — it runs only when the **user** explicitly types the slash command or asks for the skill by name.

## Where it goes

In the YAML frontmatter of a `SKILL.md` or `commands/<name>.md` file:

```yaml
---
name: nuke-cache
description: Deletes the entire build cache. Destructive — user-invoke only
disable-model-invocation: true
---

Wipe `${CLAUDE_PLUGIN_DATA}/cache/` after confirming with the user.
```

For commands:

```yaml
---
description: Reset the project to a clean state
disable-model-invocation: true
---

Run `git clean -fdx && git reset --hard origin/main` after explicit confirmation.
```

## What changes

| Aspect | Default | With `disable-model-invocation: true` |
|---|---|---|
| Listed in the model's available-skills index | yes | yes (still discoverable) |
| Listed in `/plugin` UI | yes | yes |
| Listed in slash-command palette (commands only) | yes | yes |
| Model can auto-trigger by description match | yes | **no** |
| User can fire by `/<name>` (commands) | yes | yes |
| User can ask "use the X skill" by name (skills) | yes | yes |
| Discoverable via `/help` / `/skills` listing | yes | yes |

The flag does *not* hide the skill or command — it just removes the model's autonomy to invoke it. A user who wants the behaviour can still trigger it; the model simply won't try on its own.

## Use cases

| Scenario | Why disable model invocation |
|---|---|
| **Destructive operations** | `/nuke-cache`, `/reset-project`, `/wipe-data` — you don't want the model to fire these from a related-but-not-explicit user request |
| **Long-running, expensive workflows** | `/full-test-suite`, `/rebuild-index` — model triggering could waste minutes of compute |
| **Privileged operations** | Anything that touches credentials, sends notifications, or talks to a paid API where a wrong invocation costs money |
| **Utility commands the user wants on tap** | `/copy-buffer-to-clipboard`, `/format-current-file` — useful but conceptually adjacent to almost any user request, so without the flag the model fires them constantly |
| **One-time setup commands** | `/install-deps`, `/initialize` — only meant to run once, not on every related question |

The flag is a **soft-disable**, not a security boundary. A user could still ask the model "please run the nuke-cache skill", and the model would call the skill via the normal `Skill` tool. The flag only stops the *automatic* invocation that happens when the model decides on its own that a skill matches the user's request.

## Pairs well with

- **A descriptive `description` field** — even with `disable-model-invocation`, a clear description helps users discover the command in `/help` or the slash-command palette.
- **A name that matches user vocabulary** — since the user is the only one firing it, name it the way the user would say it (`/clean`, not `/sanitise-workspace`).

## What it does NOT do

- **Does not hide the skill / command from listings.** If you want a skill nobody can see, don't ship it. There's no "private" mode.
- **Does not affect subagents.** The frontmatter flag is recognised on skills and commands only. Subagent invocation is gated by other mechanisms (the parent agent decides whether to spawn a subagent).
- **Does not affect MCP tools, hooks, or monitors.** These don't have the flag — they're invoked by their own runtime mechanisms (model decides for MCP tools, runtime fires hooks/monitors on schedule).
- **Does not require user confirmation at fire time.** It only blocks the *model* from firing. If you want a "are you sure?" prompt, write that into the skill body itself.

## Example: a destructive utility skill

```yaml
---
name: drop-database
description: |
  Drops the entire local database. Useful when iterating on schema migrations
  and you want to rebuild from scratch. NOT recommended in production environments.
  USER-INVOKE ONLY — the model will not trigger this; ask for it by name.
disable-model-invocation: true
---

# Drop database

Steps:

1. Confirm with the user that they really want to drop the database.
2. Stop running services that hold connections (`docker compose down api db`).
3. Remove the data volume (`docker volume rm myproject_db_data`).
4. Recreate empty (`docker compose up -d db`).
5. Run migrations (`npm run migrate`).

Do NOT proceed past step 1 without an explicit "yes" from the user.
```

The user types something like `/drop-database` or "use the drop-database skill" to fire it. The model never decides on its own that a question about migrations should trigger a database drop.

## See also

- [`../06_capabilities/01_skills.md`](../06_capabilities/01_skills.md) — skill frontmatter in full
- [`../06_capabilities/02_slash-commands.md`](../06_capabilities/02_slash-commands.md) — command frontmatter in full
- [`../15_reference/03_frontmatter-flags.md`](../15_reference/03_frontmatter-flags.md) — every recognised frontmatter flag in one place
- Used in the official quickstart's `hello` example
