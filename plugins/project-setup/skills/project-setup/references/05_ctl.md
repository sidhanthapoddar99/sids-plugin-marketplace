# ctl — the single entrypoint

`ctl` is a thin bash router at the repo root. It sources `scripts/common/_lib.sh` and executes one worker per verb: `scripts/<group>/<name>.sh`. No logic lives in `ctl` itself. Every verb has `--help`. Nobody types `docker compose -f` by hand.

Template: `template/ctl`, `template/scripts/`. Copy them whole; adapt by deletion. The `[ADAPT]` markers name the knobs.

## Verbs

| Group | Verb | Does |
|---|---|---|
| Development | `dev [app…] [--proxy] [--detach] [--dry-run]` | Engines in docker (`compose.db.yaml`), apps on the host with reload. `--proxy`: the same-origin dev proxy, automatic with two or more frontends. `--detach`: logs to `data/logs/`, pids to `data/run/`. |
| | `ps [--list \| kill [port…]]` | Everything running across three planes: host processes, frozen builds, containers. Attach or kill, plane-aware. |
| | `lint [app] [--staged]` | ruff, clippy, oxlint, gofmt per app. |
| Containers | `up [+modifier…] [-a] [--nqa] [-y] [--dry-run] [--list]` | The stack: `compose.base.yaml` plus modifiers. Interactive in a terminal, flag-driven otherwise. Runs migrations once before the apps. |
| | `down`, `restart`, `logs`, `exec`, `shell` | Compose passthroughs, same file list. `down` never uses `-v`: state lives in `data/`. |
| | `build [app…\|cli]` | Compose build. Frontend build args forwarded from each frontend's `.env`. `cli`: the Go binary. |
| | `clean [-y]` | Down plus caches. `data/` untouched. |
| | `health [svc…]` | One-shot health table. |
| Database | `migrate [up\|new "<msg>"\|status\|down]` | Alembic in `apps/database/postgres/`; Neo4j init. The only path that touches schema. |
| | `db shell <engine>` | psql, redis-cli, cypher-shell with `.env` credentials. |
| | `db backup`, `db restore <dir>` | Dump to `data/backups/<timestamp>/`; load back. Restore refuses while apps run. |
| Test | `test [app\|e2e]` | Each app's own suite. `e2e`: a throwaway stack. See `06_testing.md`. |
| | `gate [-q]` | The ladder: lint → check → test → build. Stops at the first red, names every rung not reached. |
| | `build save\|start\|clean` | Frozen test builds under `data/test_build/`. |
| Configuration | `setup` | `.env` from `.env.example`, secrets generated, per-frontend `.env`, `data/*` dirs, deps installed. |
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
| `+env_override` | Re-points upstreams and URLs to `${VAR}` from `.env` | A piece runs outside this compose. Refused when a mapped key is blank. |

Rules the files obey, and `ctl check` enforces:

- **Root-relative paths.** `ctl` runs compose with `--project-directory <root>`. Every path is `./apps/…`, `./data`. Never `../`. Compose loads `<root>/.env` itself.
- **Base has no ports.** Lists union across files and are never removed, so exposure can only be added, by a modifier.
- **Merge order is `base` then modifiers.** Maps (`environment`, `labels`) merge per key: a modifier overrides one key, the rest survive. Scalars (`image`, `command`) replace whole. Lists (`ports`, `depends_on`) union. `environment:` beats `env_file:`.
- **No profiles, no bare `compose.yaml`, no `compose.override.yaml`.** Every file is named. The `-f` list `ctl` prints is the contract.
- **Engines defined once**, in the db file. Base includes it. Needs compose ≥ 2.20.
- **Bind mounts, not named volumes.** `${DATA_DIR}/<engine>` on the host. Visible, backup-friendly. `data/.gitignore` keeps it out of git; `ctl setup` creates the folders.
- **Internal ports are fixed** (`api:8000`); only published host ports vary, via `${VAR}`.

`ctl up` shows the real `docker compose config` merge as a plan before running, so an invalid combination fails before anything starts.

## `ctl check` — the conformance floor

Runs as a gate rung. Fails on the first of:

- a `${VAR}` in any `config.yaml` that is not a key in `.env.example`
- a secret literal in any `config.yaml` (`*_KEY`, `*_PASSWORD`, `*_SECRET` not `${VAR}`)
- a tracked `config.local.yaml`
- `package.json`, `bun.lock`, `pnpm-workspace.yaml` at the root, in `apps/`, or directly in the frontend group folder
- `ports:` in `compose.base.yaml`
- `../` in any compose file
- `docker compose config` failing for the db file, base, base + each modifier, or the dev file
- `CLAUDE.md` not exactly `@AGENTS.md`

## Production readiness

`compose.base.yaml` is prod, so it carries prod settings. Checklist for an audit:

- [ ] `restart: unless-stopped` on every long-running service
- [ ] `healthcheck` on every app with `start_period` covering boot
- [ ] `/health` and `/ready` on every backend; compose `depends_on` uses `service_healthy`
- [ ] `stop_grace_period` ≥ the app server's graceful timeout; lifespan hooks close pools
- [ ] `deploy.resources.limits` on every service, memory above all
- [ ] logs to stdout, JSON, level from `config.yaml`; no secret logged
- [ ] migrations run once by `ctl up` before the apps, never on app boot
- [ ] TLS at the host reverse proxy in front of the stack; `client_max_body_size` and proxy timeouts set in `prod.conf.template`
- [ ] non-root user in every image; no `COPY .env`
- [ ] `data/` folders exist on the host with the right owner (`ctl setup`)
- [ ] a rollback: the previous `TAG`, or `ctl build save` snapshot

## Frozen builds

`ctl build save <target> <name>` builds a target and freezes it under `data/test_build/build-<date>-<target>-<name>/` with branch, commit and date. `ctl build start` serves one on a port. A human testing a state tests a build that cannot change under them.

## Multi-stack: several repos on one docker network

Rare. When two repos' stacks must reach each other by DNS:

- exactly one stack declares the network; every other joins it `external: true`
- service names are project-prefixed (`myapp-api`), because DNS is shared
- bring-up order is written in each README; `depends_on` cannot cross stacks
- nginx uses `resolver 127.0.0.11` and a variable in `proxy_pass`, so a down neighbour is a 502, not a crash loop
- dev configs never join the shared network; `ctl dev` must work with every other stack down

## Without a data core

`DATA_SVCS=()` in `_lib.sh`. `dev`, `up`, `setup`, `status`, `health` skip the engines. `compose.base.yaml` drops the include and the `depends_on`. `migrate` and `db` are deleted.

## Without ctl

Every app's README shows how to run it from its own folder. The root README shows the manual path. `ctl` is the sanctioned way, not the only way.
