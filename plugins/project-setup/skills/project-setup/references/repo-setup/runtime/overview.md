# Runtime overview — how mise, `ctl`, docker, and env interact

This is the **map** of the runtime triad. The three most-interacting pieces of a repo — **mise** (toolchain), **`ctl`** (the dispatcher script), and **docker** (compose) — plus the **env/config** they consume, form one causal chain. Every other doc should *link here* for the interaction story rather than re-explaining it; the per-piece detail lives in the category files listed at the bottom.

## The chain

```
.mise.toml ──pins runtimes & puts ctl on PATH──►  ctl  ──┬─► docker compose   (containers: profiles + --config + compose.m.*)
                                                         ├─► process-compose  (host dev loop)
                                                         └─► scripts/*.sh      (setup, status, migrate, …)
        root .env  ──shared vars──►  per-service config.yaml ──${VAR}──►  compose / app reads
```

Read it as: **mise makes `ctl` callable → `ctl` is the single entrypoint → `ctl` delegates to compose, a process runner, and subscripts → all of them read the same env/config layering.**

## Who owns what

| Piece | Responsibility | Detail doc |
|---|---|---|
| **mise** | Pin language/tool versions; project-scoped PATH so `ctl` is callable bare | `runtime/mise.md` |
| **`ctl`** | The *only* entrypoint. A **thin wrapper** that routes to compose / process-compose / `scripts/*.sh` — it assembles flags, it does not implement | `runtime/script-overview.md` |
| **`scripts/*.sh`** | The bodies `ctl` delegates to — each owns one job (setup, status, migrate, dev-host, health-wait) | `runtime/script-usage.md` |
| **docker compose** | Container stack: a profiled base + `--config` configs + `compose.m.*` modifiers | `runtime/docker-compose-structure.md` |
| **env / config** | Root `.env` (shared) → per-service `config.yaml` (`${VAR}`) → real env wins | `env-and-config/` |

## Two run surfaces

`ctl` splits cleanly by *where code runs*:

- **`ctl dev` — on the host.** Apps run directly (hot reload); only the data core runs in containers, which `ctl dev` auto-starts (with ports). This is the day-to-day loop. → `runtime/script-overview.md`
- **`ctl up [profile…] [--config=…] [--<modifier>…]` — in docker.** Profiles pick services, `--config` swaps the deployment config (e.g. `--config=prod`), modifiers layer cross-cutting tweaks (`--expose`, `--traefik`). Production is `ctl up app edge --config=prod`. → `runtime/docker-compose-structure.md` + `runtime/script-usage.md`

There is **no `ctl prod` verb** — prod is a config, not a command.

## The three startup paths (README contract)

Every README documents three ways to start, each for a different need:

1. **`ctl` (preferred)** — `ctl dev` locally / `ctl up …` in docker. Fast onboarding.
2. **Raw `docker compose`** — understand/debug what `ctl` assembles.
3. **No-docker host run** — `cd apps/<svc> && <run>` for IDE-debugger attach.

If any path is broken, the repo has invisible debt — `/ps-setup audit` checks for all three. Complex (Layout 05) setups add a fourth: building the orchestrator binary (`runtime/complex-setups.md`).

## When this isn't enough

If you need structurally different stacks (single-node vs cluster vs prod) or `ctl` grows structured state across runs, escalate to multi-mode `docker/<mode>/` trees + a binary orchestrator → `runtime/complex-setups.md` (Layout 05).

## Detail docs (the single source for each)

- `runtime/mise.md` — version contract + bare-name PATH
- `runtime/docker-compose-structure.md` — profiles vs `--config` vs `compose.m.*`; `docker/` layout + path discipline
- `runtime/docker-bind-mounts.md` · `runtime/docker-nested-data-dir.md` · `runtime/docker-internal-ports.md`
- `runtime/script-overview.md` — the `ctl`/`scripts` model + the `scripts/` structure & map
- `runtime/script-usage.md` — command surface, dispatcher skeleton, setup/status, host loop, the three startup-path commands
- `runtime/complex-setups.md` — multi-mode trees + binary orchestrator (Layout 05)
- `env-and-config/` — the env/config layering the runtime consumes
