# What the Model Sees

The model — Claude inside the session — has no concept of "the plugin." It sees the unpacked capabilities the plugin ships, alongside hand-authored capabilities at user/project scope, with no structural distinction.

## Capabilities visible to the model

| Capability | How it appears | When it loads |
|---|---|---|
| **Skill** | Name + description in a system reminder; body loads on trigger | Description: always. Body: when the model decides to use it |
| **Slash command** | Name + description in available-commands list | Body: when fired by the user, or model invokes it |
| **Subagent** | Name + description in available-agents list | Spawned via `Agent` tool; runs in fresh context |
| **MCP tool** | `mcp__<server>__<tool>` in the tool list | Server starts at session init; tools always visible |
| **`bin/` wrapper** | An executable in `$PATH` | Always callable via `Bash` |

Each of these the model can decide to use. For skills and commands, the decision is description-driven — the description is the entire signal until the model commits to using the capability.

## What the model does NOT see

| Thing | Why |
|---|---|
| **Hooks** | Hooks fire in the runtime — before/after tool calls, on session events. The model never knows which ones are registered or that they fired |
| **The plugin folder** | The plugin is packaging; it has no representation in model context |
| **`plugin.json` / `marketplace.json`** | Manifests are metadata for the runtime |
| **`enabledPlugins` settings** | Scope decisions happen before the model gets context |
| **The marketplace** | The model never reasons about where capabilities came from |
| **Sensitive `userConfig` values** | Values marked `sensitive: true` go to the OS keychain and are *not* substituted into skill/agent content (only into MCP/LSP/hook/monitor commands and as env vars to subprocesses) |

Hooks that *modify* model context (e.g. `UserPromptSubmit` with stdout becoming a system reminder) do reach the model — but as injected text, not as "a hook fired." The model sees the text and processes it like any other input.

## In context vs. on demand

There are three loading tiers for model-visible content:

| Tier | Cost | Examples |
|---|---|---|
| **Always loaded** | ~50–100 words per skill, smaller for commands | Skill descriptions, command descriptions, subagent descriptions, tool list entries |
| **Loaded on trigger** | Body of the matched capability | Skill body when the description matches; slash command body when fired |
| **Loaded on demand** | Read individually as the model needs them | `references/<topic>.md` files inside skills, files cited from skill bodies, files Claude reads via `Read` tool |

This **progressive disclosure** is how skills stay cheap to ship even when they're large. A 5,000-line skill costs ~50 words of context until it triggers. After triggering, only the body is loaded. References are read individually.

Description quality is therefore load-bearing: a vague description means the skill never triggers (bad), and an over-broad description means it triggers when irrelevant (also bad — wastes context).

## How MCP tools appear

Every MCP server registered via `.mcp.json` exposes tools that the runtime translates into entries in the model's tool list, namespaced as `mcp__<server>__<tool>`. From the model's perspective, an MCP tool is indistinguishable from a built-in tool — same calling conventions, same JSON-schema-typed inputs.

The puppeteer server's `click` tool, for example, appears as `mcp__puppeteer__puppeteer_click`. The double-prefix (server name + tool name) lets multiple MCP servers coexist without name collisions in the model's tool list.

## How `bin/` wrappers appear

The runtime adds every enabled plugin's `bin/` to `$PATH` at session start. From the model's perspective, every executable in `bin/` is just a system command — callable via the `Bash` tool the same as `git` or `ls`.

This is why `bin/` is the cheapest way to give the model access to bundled plugin tooling: zero context cost (the wrapper isn't in any tool list), zero per-call protocol (just a Bash invocation), and natural composition with shell pipelines.

## Implication for authoring

Two practical consequences fall out of "the model only sees capabilities":

1. **Names matter for collision, not for ownership.** The model sees `documentation-guide:documentation-guide` as one skill name. The `:` is a collision-avoidance prefix, not a structural relationship — see [04_naming-and-namespacing.md](./04_naming-and-namespacing.md).
2. **Description quality is the entire user-experience.** No amount of polish in the SKILL.md body matters if the description doesn't trigger. Same for slash commands and subagents.

## See also

- [02_what-the-runtime-sees.md](./02_what-the-runtime-sees.md) — the other side of the split
- [03_packaging-vs-capabilities.md](./03_packaging-vs-capabilities.md) — why hand-authored and plugin-shipped capabilities are indistinguishable
- [Capabilities](../06_capabilities/00_index.md) — deep dive on each capability type
- [Skills](../06_capabilities/01_skills.md) — description-as-trigger pattern in depth
