# Runtime overview — how mise, `ctl`, docker, and env interact

This is the **map** of the runtime triad. The three most-interacting pieces of a repo — **mise** (toolchain), **`ctl`** (the dispatcher script), and **docker** (compose) — plus the **env/config** they consume, form one causal chain. Every other doc should *link here* for the interaction story rather than re-explaining it; the per-piece detail lives in the category files listed at the bottom.

## The chain

```
.mise.toml ──pins runtimes & puts ctl on PATH──►  ctl  ──┬─► docker compose   (containers: standalone config + compose.m.* modifiers)
                                                         ├─► process-compose  (host dev loop)
                                                         └─► scripts/*.sh      (setup, status, migrate, …)
        root .env  ──shared vars──►  per-service config.yaml ──${VAR}──►  compose / app reads
```

Read it as: **mise makes `ctl` callable → `ctl` is the single entrypoint → `ctl` delegates to compose, a process runner, and subscripts → all of them read the same env/config layering.**

## Who owns what

| Piece | Responsibility | Detail doc |
|---|---|---|
| **mise** | Pin language/tool versions; project-scoped PATH so `ctl` is callable bare | `references/2-repo/runtime/mise.md` |
| **`ctl`** | The *only* entrypoint. A **thin wrapper** that routes to compose / process-compose / `scripts/*.sh` — it assembles flags, it does not implement | `references/2-repo/runtime/script-overview.md` |
| **`scripts/*.sh`** | The bodies `ctl` delegates to — each owns one job (setup, status, migrate, dev/host, health-wait) | `references/2-repo/runtime/script-usage.md` |
| **docker compose** | Container stack: base + a standalone `config` (replaces base) + `compose.m.*` modifiers (profile-less) | `references/2-repo/runtime/docker-overview.md` |
| **env / config** | Root `.env` (shared) → per-service `config.yaml` (`${VAR}`) → real env wins | `references/2-repo/env-and-config/` |

## Two run surfaces

`ctl` splits cleanly by *where code runs*:

- **`ctl dev` — on the host.** Apps run directly (hot reload); only the data core runs in containers, which `ctl dev` auto-starts (with ports). This is the day-to-day loop. → `references/2-repo/runtime/script-overview.md`
- **`ctl up [config] [--modifier "a,b"]` — in docker.** Profile-less, two axes: an optional standalone `config` (a `compose.<name>.yaml` that *replaces* base — `data`, `prod`) + stackable `--modifier` overlays (`expose`, `traefik`). Bare `ctl up` in a TTY is interactive (config → modifiers → plan → confirm). Production is `ctl up prod`. → `references/2-repo/runtime/docker-overview.md` + `references/2-repo/runtime/script-usage.md`

There is **no `ctl prod` verb** — prod is a config, not a command. There are **no profiles** in the default model (they're the rare multi-group escalation — `references/2-repo/runtime/complex-setups.md`).

## The three startup paths (README contract)

Every README documents three ways to start, each for a different need:

1. **`ctl` (preferred)** — `ctl dev` locally / `ctl up …` in docker. Fast onboarding.
2. **Raw `docker compose`** — understand/debug what `ctl` assembles.
3. **No-docker host run** — `cd apps/<svc> && <run>` for IDE-debugger attach.

If any path is broken, the repo has invisible debt — `/ps-setup audit` checks for all three. Complex (Layout 05) setups add a fourth: building the orchestrator binary (`references/2-repo/runtime/complex-setups.md`).

## When this isn't enough

If you need structurally different stacks (single-node vs cluster vs prod) or `ctl` grows structured state across runs, escalate to multi-mode `docker/<mode>/` trees + a binary orchestrator → `references/2-repo/runtime/complex-setups.md` (Layout 05).

## Detail docs (the single source for each)

- `references/2-repo/runtime/mise.md` — version contract + bare-name PATH
- `references/2-repo/runtime/docker-overview.md` — standalone config vs `compose.m.*` modifiers (profile-less) + expose tiers; `docker/` layout + path discipline
- `references/2-repo/runtime/docker-details.md` — bind-mounts, the `data/` layout, internal-vs-host ports, anchors
- `references/2-repo/runtime/script-overview.md` — the `ctl`/`scripts` model + the `scripts/` structure & map (incl. `_select.sh`)
- `references/2-repo/runtime/script-usage.md` — command surface, dispatcher skeleton, the interactive `ctl up` flow + plan, setup/status, host loop, the three startup-path commands
- `references/2-repo/runtime/script-alternatives.md` — adapting off the recommended tools (mise/docker/uv/bun)
- `references/2-repo/runtime/no-data-core.md` — `DATA_SVCS=()` topology swap for DB-less projects
- `references/2-repo/runtime/complex-setups.md` — profiles as the advanced escalation; multi-mode trees + binary orchestrator (Layout 05)
- `references/2-repo/env-and-config/` — the env/config layering the runtime consumes
