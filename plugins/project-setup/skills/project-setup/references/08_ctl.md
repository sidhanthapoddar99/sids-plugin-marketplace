# ctl — the single entrypoint

`ctl` is a thin bash router at the repo root. It sources `scripts/common/_lib.sh` and executes one worker per verb: `scripts/<group>/<name>.sh`. No logic lives in `ctl` itself. Every verb has `--help`. Nobody types `docker compose -f` by hand.

Template: `template/ctl`, `template/scripts/`. Copy them whole; adapt by deletion. The `[ADAPT]` markers name the knobs.

## Verbs

| Group | Verb | Does |
|---|---|---|
| Development | `dev [app…] [--proxy] [--detach] [--dry-run]` | Engines in docker (`compose.db.yaml`), apps on the host with reload. `--proxy`: the same-origin dev proxy, automatic with two or more frontends. `--detach`: logs to `logs/dev/`, pids to `logs/run/`. |
| | `ps [--list \| kill [port…]]` | Everything running across three planes: host processes, frozen builds, containers. Attach or kill, plane-aware. |
| Containers | `up [+modifier…] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list]` | The stack: `compose.base.yaml` plus modifiers, every service or a subset. In a terminal: pick modifiers → pick services (all preselected) → plan → confirm. Flags skip their prompt; no TTY = defaults. Runs migrations once before any app. |
| | `down`, `restart`, `logs`, `exec`, `shell` | Compose passthroughs, same file list. `down` never uses `-v`: state lives in `data/`. |
| | `build [app…\|cli]` | Compose build. Build args are prefixes interpolated from `.env.proxy`. `cli`: the Go binary. |
| | `clean [-y]` | Down plus caches. `data/` untouched. |
| | `health [svc…]` | One-shot health table. |
| Database | `migrate [up\|new "<msg>"\|status\|down]` | Alembic in `apps/database/postgres/`; Neo4j init. The only path that touches schema. |
| | `db shell <engine>` | psql, redis-cli, cypher-shell with `.env.secrets` credentials. |
| | `db backup`, `db restore <dir>` | Dump to `logs/backups/<timestamp>/`; load back. Restore refuses while apps run. |
| Administration | `manage ops <list\|create\|disable\|enable\|reset-password\|lockout>` | Operator accounts, without the web auth flow. Below. |
| | `manage settings <list\|get\|set>` | Platform settings, value parsed as JSON. |
| Test | `test [app\|e2e]` | Each app's own suite. `e2e`: a throwaway stack. See `10_testing.md`. |
| | `build save\|start\|clean` | Frozen test builds under `logs/test_build/`. `09_production.md`. |
| Gates | `gate [all] [-q] [--memory SIZE]` | The ladder: lint → typecheck → dead → audit → test → check → build → e2e. Stops at the first red, names every rung not reached. One run at a time, under a memory lid. |
| | `gate <rung> [-q]` | One rung. `gate lint [app] [--staged]` and `gate typecheck [app]` take a target; the others take none. |
| | `gate clones\|fuzz\|perf` | By name. Never in the ladder. |
| Configuration | `setup` | `.env.secrets`, `.env.data`, `.env.proxy` from their templates, secrets generated, `data/*` and `logs/*` dirs, deps installed. |
| | `check` | Conformance floor. Below. |
| | `status` | Read-only doctor: env, runtimes, deps, docker, health, stack. Never dies. |

## The compose model

| File | Role | Run by |
|---|---|---|
| `docker/compose.db.yaml` | The engines alone. Loopback ports, bind mounts under `${DATA_DIR}`. | `ctl dev` |
| `docker/compose.dev.yaml` | The dev proxy: one nginx on the host network. | `ctl dev --proxy` |
| `docker/compose.base.yaml` | The whole stack. `include:`s the db file. **No ports. No `env_file`.** This is prod. | `ctl up` |
| `docker/compose.m.<name>.yaml` | Modifiers. Discovered by filename. | `ctl up +<name>` |

| Modifier | Adds | When |
|---|---|---|
| `+expose_web` | `web` on `${HTTP_PORT}` / `${HTTPS_PORT}` | The default. Prod. |
| `+expose` | Every app port to the host | Debug. Never prod. |
| `+env_override` | Re-points upstreams and URLs to `${VAR}` from `.env.proxy` and `.env.secrets` | A piece runs outside this compose. Refused when a mapped key is blank. |

Rules the files obey, and `ctl check` enforces:

- **Root-relative paths.** `ctl` runs compose with `--project-directory <root>`. Every path is `./apps/…`, `./data`. Never `../`. `ctl` passes `--env-file .env.secrets --env-file .env.data --env-file .env.proxy`; compose reads no `.env` on its own. Needs compose ≥ 2.24.
- **Base has no ports.** Lists union across files and are never removed, so exposure can only be added, by a modifier.
- **Merge order is `base` then modifiers.** Maps (`environment`, `labels`) merge per key: a modifier overrides one key, the rest survive. Scalars (`image`, `command`) replace whole. Lists (`ports`, `depends_on`) union. `environment:` beats `env_file:`.
- **No profiles, no bare `compose.yaml`, no `compose.override.yaml`.** Every file is named. The `-f` list `ctl` prints is the contract.
- **Engines defined once**, in the db file. Base includes it. Needs compose ≥ 2.20.
- **Bind mounts, not named volumes.** `${DATA_DIR}/<engine>` on the host. Visible, backup-friendly. `data/.gitignore` keeps it out of git; `ctl setup` creates the folders.
- **Internal ports are fixed** (`api:8000`); only published host ports vary, via `${VAR}`.

`ctl up` shows the real `docker compose config` merge as a plan before running, so an invalid combination fails before anything starts. With `--services`, the plan still lists every service in the file set and marks the subset; an app in the subset brings the whole data core and the migration step with it, an engine alone does not.

**The docker guard runs first, by name.** Every docker verb calls `require_docker` before its first compose call. It tells three faults apart: not installed, engine not running, compose plugin missing. Compose itself reports a dead engine as a config error, which is how an earlier `up.sh` printed "invalid modifier combination" for "Docker is not running". `ctl status` shows the same three states without dying.

The `scripts/` groups are `common config dev container db test gate`. A gate rung never holds logic: it calls the same worker its dev verb calls (`gate/test.sh` → `test/test.sh`); lint and typecheck have no separate dev verb, the rung is the worker, so the gate and the loop cannot drift.

## `ctl check` — the conformance floor

Runs as a gate rung. Fails on the first of:

- a `${VAR}` in any `config.yaml` that is not a key in one of the three `.env.*.template` files
- a `*_PASSWORD` / `*_KEY` / `*_SECRET` key outside `.env.secrets.template`; a `.env.proxy.template` key not ending `_HOST/_PORT/_PREFIX/_URL`; a `.env.data.template` key not ending `_DIR`
- a secret literal in any `config.yaml` (`*_KEY`, `*_PASSWORD`, `*_SECRET` not `${VAR}`)
- a tracked `config.local.yaml`
- `package.json`, `bun.lock`, `pnpm-workspace.yaml` at the root, in `apps/`, or directly in the frontend group folder
- `ports:` in `compose.base.yaml`
- `../` in any compose file
- `docker compose config` failing for the db file, base, base + each modifier, or the dev file
- `CLAUDE.md` not exactly `@AGENTS.md`

## `ctl manage` — the break-glass console

The one path to operator identity that does not go through the web. It seeds the first SuperAdmin, resets a password when the admin UI is down, flips a platform setting. Model: `neura-cloud-vault/scripts/admin/manage.sh` → `apps/api-admin/manager.py`. Template: `template/scripts/admin/manage.sh`, `template/apps/example-api-python/manager.py`.

| Rule | Why |
|---|---|
| `manage.sh` is a thin forward: `cd <admin backend> && uv run python manager.py "$@"`. Bare `ctl manage` prints ctl's help; anything else reaches argparse, so `ctl manage ops --help` works. | One implementation. The shell layer adds nothing but the env guard. |
| `manager.py` lives at the backend root, beside `app/`. It imports the app's loader and `core/security.py`, never a router. | It is a program, not a domain. Same hashing and connection values as the service; no second copy. |
| It runs without the web auth flow. Access to the host is the boundary. | Nothing else can be: it exists for when auth is broken. So it runs on the host or over SSH, never in a container with a published port. |
| Every mutating action writes to `operator_audit` (actor `console`, action, target, outcome). | An unaudited break-glass is a backdoor. |
| Operators are disabled, never deleted. | The audit history must keep its subject. |
| Operator identity is never reachable through public signup or OAuth. The first admin comes from `ctl manage ops create --super`. | The identity plane is separate (`03_routing.md`, case 7). |
| A generated password (`--auto-password`) is printed once, alone on its line, and never logged. | It is a secret in transit. |
| Needs the data core up: `ctl dev`, or `ctl up --services=postgres,redis`. | It talks to the tables directly. |

Products without an operator plane delete `scripts/admin/` and `manager.py`.

## Without a data core

`DATA_SVCS=()` in `_lib.sh`. `dev`, `up`, `setup`, `status`, `health` skip the engines. `compose.base.yaml` drops the include and the `depends_on`. `migrate` and `db` are deleted. `require_env` stays strict only if the apps still read secrets; `status` and `health` point at the app services and their healthchecks instead.

## Without ctl

Every app's README shows how to run it from its own folder. The root README shows the manual path. `ctl` is the sanctioned way, not the only way: raw `docker compose --project-directory . --env-file … -f docker/compose.base.yaml` must keep working beside it, which is why `ctl` never carries state compose does not see.

## When ctl is not enough

`ctl` stays a bash router. Escalate to a compiled orchestrator (Go) only when a verb needs structured state across runs: a plan file, a lock that outlives a shell, a fleet of hosts. Line count alone is not the trigger. The state file is documented and versioned, and the plain compose invariant above still holds.

## The ctl shape, as a check

`ctl check` can prove the router is a router: `ctl` sources `_lib.sh`; every substantive verb is `run`-routed to `scripts/<group>/<name>.sh`; every worker starts with the preamble (`set -euo pipefail`, sources `_lib.sh`) and answers `--help`. A single-file `ctl` with logic inside is a red finding.
