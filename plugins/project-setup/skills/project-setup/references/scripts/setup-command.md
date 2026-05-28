# `ctl setup` + `ctl status` — the two project-custom subcommands

No `setup.dev.sh`, `setup.prod.sh`, or `install.sh` at root. Configuration lives behind two `ctl` verbs:

- **`ctl setup`** — an interactive wizard that fills `.env` / `config.local.yaml`.
- **`ctl status`** — a config doctor that reports whether the project is correctly configured.

These are the **two subcommands whose bodies are necessarily project-specific** (which env keys, which services, frontend-vs-backend checks). Every other `ctl` verb is largely uniform across projects; these two route to `scripts/setup.sh` and `scripts/status.sh`, which you write per project. The *command surface* stays standard; the *logic* varies.

## `ctl setup` — fill config interactively

First-run is `ctl setup` → `ctl dev`. Setup is explicit (not folded silently into a bare run) so the user knows configuration happened and can re-run it any time.

What `scripts/setup.sh` does:

1. Copy `.env.example` → `.env` if missing (never overwrite an existing `.env`).
2. Walk the **REQUIRED** keys (marked in `.env.example`) and prompt for each, showing the current value.
3. Generate secrets the user shouldn't invent — `openssl rand -hex 32` for tokens, db passwords.
4. Optionally seed `config.local.yaml` for dev overrides (cross-link `references/env-and-config/config-local-overrides.md`).
5. Ensure bind-mount data dirs exist (`mkdir -p data/postgres/pgdata data/redis/data`).
6. End by printing `ctl status` so the user sees a green board.

```bash
# scripts/setup.sh (sketch)
set -euo pipefail
[[ -f .env ]] || cp .env.example .env
# prompt REQUIRED blanks; generate secrets; mkdir -p data dirs
# write/update .env and (optionally) config.local.yaml
exec bash scripts/status.sh
```

Keep prompts idempotent — re-running `ctl setup` should top up missing values, not clobber good ones.

## `ctl status` — the config doctor

`ctl status` answers "is this project correctly configured to run?" — **before** you try `ctl dev` and hit a confusing runtime error. It's read-only.

Checks (project-specific, but the shape is consistent):

| Check | Example |
|---|---|
| `.env` exists and matches `.env.example` schema | no missing keys, no empty REQUIRED values |
| `config.local.yaml` present (dev) | warn if absent — dev defaults won't apply |
| Per-service config | backend `config.yaml` valid; frontend `.env` has its `VITE_*`/`NEXT_PUBLIC_*` |
| Dependencies reachable | data containers up? ports free? `mise` tools installed? |
| Secrets not placeholder | REQUIRED keys aren't still `changeme` |

Report per area (backend / frontend / infra), green/yellow/red, with the fix for each red. `ctl status <service>` narrows to one service.

```
$ ctl status
✓ .env present, matches .env.example
! config.local.yaml not set — using config.yaml defaults
✓ backend: config.yaml valid, DATABASE_URL set
✗ frontend: VITE_API_BASE_URL empty — set it in apps/web/.env
✓ infra: postgres + redis healthy
```

`ctl status` shares logic with `scripts/check-env.sh` (see `references/scripts/subscripts.md`) — `check-env` is the env-schema diff; `status` is the broader, per-service doctor that calls it.

## Why explicit `setup`, not folded-into-bare-run

The old pattern folded first-run setup into a bare `./dev`. The `ctl` model makes it explicit because:

- **`ctl dev` has one job** — run the host loop. It *checks* config and tells you to run `ctl setup` if unconfigured; it doesn't silently mutate `.env` mid-launch.
- **`ctl setup` is re-runnable** on its own — "I added a new service, re-fill its keys" without launching anything.
- **`ctl status` gives a fast yes/no** without side effects — the thing you run when "it won't start" and you don't know why.

`ctl dev`'s only config interaction is the guard: if `.env` is missing, it stops and says `run ctl setup` (see the `require_env` helper in `references/scripts/global-wrapper-dispatcher.md`).

## Production deploy

Production is `ctl prod` (full docker, prod overlay). Prod secrets are injected as **real environment variables** (`.env.production` via compose `env_file`, or a secret manager), never via `ctl setup`'s interactive prompts — see `references/env-and-config/env-precedence.md` and `references/env-and-config/secrets-matrix.md`.

## Anti-patterns

- `setup.sh` + `start.sh` + `dev.sh` at root — four contracts; collapse to `ctl` verbs.
- README "first run `make install`, then `make dev`" — it's `ctl setup` then `ctl dev`.
- `ctl dev` silently editing `.env` on launch — guard and instruct instead; mutation belongs in `ctl setup`.
- A `status` that just greps for files — it should check reachability and REQUIRED-value-ness, not mere presence.
- Generating prod secrets via the interactive wizard — prod injects real env vars, doesn't prompt.

## See also

- `references/scripts/global-wrapper-dispatcher.md` — the dispatcher; `require_env` guard
- `references/scripts/subscripts.md` — `scripts/setup.sh`, `scripts/status.sh`, `scripts/check-env.sh`
- `references/env-and-config/env-precedence.md` — load order; prod injects real env vars
- `references/env-and-config/config-local-overrides.md` — `config.local.yaml` precedence
