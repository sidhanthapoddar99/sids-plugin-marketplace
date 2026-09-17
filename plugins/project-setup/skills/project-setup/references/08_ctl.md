# ctl — the single entrypoint

`ctl` is a thin bash router at the repo root. It sources `scripts/common/_lib.sh` and executes one worker per verb: `scripts/<group>/<name>.sh`. No logic lives in `ctl` itself. Every verb has `--help`. Nobody types `docker compose -f` by hand.

Template: `template/ctl`, `template/scripts/`. Copy them whole; adapt by deletion. The `[ADAPT]` markers name the knobs.

The verb table below is the floor, not the ceiling. A project adds the verbs its work needs (`ctl train`, `ctl sqlx-prepare`, `ctl mobile-api-codegen`, `ctl seed`, `ctl deploy`) the same way every existing verb is built: one worker at `scripts/<group>/<name>.sh` with the preamble, `--help`, and one `run <group>/<name>` line in `ctl`. New groups are fine (`scripts/ml/`, `scripts/admin/`). Two rules hold: logic never lives in `ctl` itself, and every added verb appears in `ctl --help` and in the `AGENTS.md` Commands section. Verbs that stop being used are deleted, not left as residue.

## Verbs

| Group | Verb | Does |
|---|---|---|
| Development | `dev [app…] [--proxy] [--detach] [--dry-run]` | The data core through `ctl up preset dev --nqa -y`, the reserved preset (engines on loopback, the schema one-shots with them), then the apps on the host with reload. Apps run on the host because a debugger attaches and file events are native; source is never bind-mounted into a dev container. `--proxy`: the same-origin dev proxy, automatic with two or more frontends. `--detach`: logs and ownership records below the configured `LOGS_DIR`. `--no-core`: skip the data core. `--nqa`: skip the app picker. `dev` guards and instructs (`run ctl setup`); it never edits config mid-launch. |
| | `ps [--list \| kill [port…]]` | Everything running across three planes: host processes, frozen builds, containers. Attach or kill, plane-aware. |
| | `stop [--dry-run]` | Stop this project's recorded host groups and frozen servers, then its containers. Keep containers, data and volumes. No prompts. |
| Containers | `up [--config c] [+modifier…] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list]` | A stack shape (`compose.<config>.yaml`, `base` by default) plus modifiers, every service or a subset. In a terminal: pick a config → pick the modifiers that fit → pick services (all preselected) → plan → confirm. Flags skip their prompt. No TTY: the plan prints and the run refuses without `-y`; `--nqa -y` is the scripted form. Compose orders engines, schema one-shots, apps by itself. `08a_ctl_docker.md`. |
| | `up preset [<name>] [-y]`, `up preset --list`, `up set-preset [<name>]` | A saved `up` line from `docker/presets.yaml`: run one with no prompts, list them, or walk the pickers and save. `08a_ctl_docker.md` § 4. |
| | `down`, `restart`, `logs`, `exec`, `shell` | Compose passthroughs against the `base` file. `down` never uses `-v`: state lives in `data/`. |
| | `build [app…\|cli]` | Compose build. Build args are prefixes interpolated from `.env`. `cli`: the Go binary. |
| | `clean [-y]` | Down plus caches. `data/` untouched. |
| | `health [svc…]` | One-shot health table. |
| Database | `db migrate [up\|new "<msg>"\|status\|down]` | The `migrate` and `neo4j-init` one-shots from `compose.db.yaml`, run inside the compose network with `docker compose run --rm --no-deps`. The only path that touches schema. The same one-shots run on their own whenever the db config comes up. Needs the engines up. |
| | `db shell <engine>` | psql, redis-cli, cypher-shell with `.env` credentials. |
| | `db backup`, `db restore <dir>` | Dump to `${BACKUP_DIR}/<timestamp>/`; load back. Restore validates the PostgreSQL archive before mutation and refuses while configured app containers or recorded host processes run. |
| Administration | `manage ops <list\|create\|disable\|enable\|reset-password\|lockout>` | Operator accounts, without the web auth flow. Below. |
| | `manage settings <list\|get\|set>` | Platform settings, value parsed as JSON. |
| Test | `test [app\|e2e]` | Each app's own suite. `e2e`: a throwaway stack. See `10c_dynamic-tests.md`. |
| | `build save\|start\|clean` | Frozen test builds under `${LOGS_DIR}/test_build/`. `09_production.md`. |
| Gates | `gate [all] [-q] [--memory SIZE]` | The ladder: lint → typecheck → dead → audit → test → check → build → e2e, trimmed to the rungs `AGENTS.md` lists. The floor is `lint typecheck test check`. Stops at the first red, names every rung not reached. One run at a time, under a memory lid. `10b_static-checks.md`. |
| | `gate static\|dynamic [-q]` | The listed rungs that read the code, or the ones that run it. Ladder order kept. |
| | `gate <rung> [-q]` | One rung. `gate lint [app] [--staged]` and `gate typecheck [app]` take a target; the others take none. |
| | `gate clones\|fuzz\|perf` | By name. Never in the ladder. |
| Configuration | `setup` | `.env` from its template, declared local credentials generated, configured storage dirs created, toolchains installed and activated, source-package dependencies installed. |
| | `check` | The repo contract. Below. |
| | `status` | Read-only doctor: env, runtimes, deps, docker, health, stack. Never dies. |

## The compose model

`08a_ctl_docker.md` is the home of this. In one line: a **config** (`compose.<name>.yaml`, one stack shape, `base` is prod and the default) plus **modifiers** (`compose.m.<name>.yaml`, only the ones compose accepts on that config) plus a **service subset** (only those and their `depends_on` chain build and run), saved as a **preset** (`docker/presets.yaml`, one `ctl up` line per name), with **`include:`** as the way one config borrows another file. A config never publishes a port. The plan is the real `docker compose config` merge.

Constants that hold everywhere: root-relative paths with `--project-directory <root>`; the root .env file passed with `--env-file`, Compose uses the explicitly selected file (compose ≥ 2.24); no profiles, no bare `compose.yaml`, no `compose.override.yaml`; bind mounts under `${DATA_DIR}`, never named volumes; internal ports fixed (`api:8000`), only published host ports vary.

**The docker guard runs first, by name.** Every docker verb calls `require_docker` before its first compose call. It tells three faults apart: not installed, engine not running, compose plugin missing. Compose itself reports a dead engine as a config error, which is how an earlier `up.sh` printed "invalid modifier combination" for "Docker is not running". `ctl status` shows the same three states without dying.

The `scripts/` groups are `common config dev container db admin test gate`. A gate rung never holds logic: it calls the same worker its dev verb calls (`gate/test.sh` → `test/test.sh`); lint and typecheck have no separate dev verb, the rung is the worker, so the gate and the loop cannot drift.

## Setup and tool availability

`scripts/config/_discovery.sh` discovers source manifests below `apps/`, including nested packages, to a maximum depth of 12. It prunes dependency, build, cache, vendor and generated directories and does not follow directory symlinks, so installing a source package cannot recurse into its installed dependencies. Cargo identifies the owning workspace before fetching; one workspace is fetched once, and an excluded independent crate keeps its own fetch. Setup fails on discovery or dependency-install errors. The conformance version scan uses the same source discovery.

`scripts/common/_tools.sh` installs declared mise toolchains during setup, then activates them in the same invocation. It evaluates only the shell environment emitted by mise, never the contents of `.env`. Activation preserves application environment overrides while selecting tool paths. `require_tools` activates without installing and verifies that each requested executable runs. A selected app asks only for its own runtime; missing required tools are errors, not successful skips. Setup's credential declarations are specified in `02_env.md`.

The Rust example declares `cargo:cargo-watch` in `.mise.toml` because its development command uses that executable. Remove its declaration when removing the Rust example; select and pin a replacement if the project chooses another watcher. Explicit `cargo:` tool identifiers use the [mise Cargo backend](https://mise.jdx.dev/dev-tools/backends/cargo).

## Development readiness and ownership

Adapt `scripts/dev/_apps.sh`: each app declares its command, required tools, readiness probe and timeout. The shipped API and engine probes call their prefixed `/ready` endpoint; frontend probes exercise HTTP. Change a probe when the app needs a stronger condition. A listening port alone never permits a successful skip: a pre-existing listener must pass the same probe, and it is left running if this launch fails.

`scripts/common/_process.sh` installs cleanup before launch and starts each owned command in its own process group. Failed startup, bounded probe timeout, early exit and interruption return nonzero and clean up owned groups, including normal descendants. Detached success requires all selected apps ready; foreground mode monitors owned processes and reports unexpected exits. Readiness is a point-in-time check, not a promise that a dependency stays available.

Ownership records live in `LOGS_DIR/run/<name>.process/`, including a PID and its process-start identity; output lives in `LOGS_DIR/dev/<name>.log`. Identity checks prevent a reused PID from being treated as the old process. Attach, stop and frozen-build commands use the same configured paths. The host-process implementation requires Linux or WSL, Bash, `/proc`, `setsid` and GNU coreutils. Programs that deliberately escape their process group need a project-specific supervisor.

The development proxy has its own readiness endpoint. Reuse a running proxy; on failed startup or interruption stop only the proxy container started by this invocation. Data-core startup uses the bounded production-start helper; it does not continue after failed readiness.

## `ctl stop` — project-wide shutdown

Worker: `template/scripts/dev/stop.sh`; lifecycle helper: `template/scripts/common/_process.sh`. Bare `ctl stop` stops foreground and detached managed groups from the configured `LOGS_DIR/run`, including watchers and frozen-build servers. It never selects host processes by port. `--dry-run` lists targets without signals, record cleanup or container changes; Docker queries still run.

Each new record stores the project root, PID and start identity. A live legacy record with a start identity needs a working directory inside this project to establish ownership. Live PID-only records and foreign records fail closed, because they cannot safely identify this project's process. Stale records are cleaned; reused PIDs are not signalled. Keep `LOGS_DIR` project-specific. Processes deliberately detached from the managed group need their own supervisor cleanup.

Shutdown sends TERM and allows up to 20 seconds per group for watcher cleanup before verified KILL. `PROCESS_STOP_TIMEOUT` may set a positive integer grace in seconds. Remaining live groups or signal failures retain their records and return nonzero. A host failure leaves containers running, so databases cannot disappear underneath an unresolved writer.

Docker targets must match both the resolved Compose project name and the exact project working-directory label. This includes the dev proxy and orphaned services from other stack configurations of the same project. Non-data containers stop before the `DATA_SVCS` engines. Update that existing data-service list when adapting the stack, because it defines shutdown order. Failed writer shutdown leaves engines running. Docker checks and stop calls are bounded; missing or unreachable Docker returns nonzero after host cleanup. Repeating a successful stop is safe. Do not launch new project workloads concurrently with shutdown; this command is not a project-wide launch lock.

## `ctl check` — the repo contract

Runs directly, and as the `check` rung of the ladder. It runs every rule, prints every failure with its file, and exits 0 only when all of them passed, because a check that stops at the first red hides the second one and a check that prints an ok line under a failure teaches the reader to skip the output. This list is the one home of what it proves; `02_env.md`, `01_layout.md` and `11_conventions.md` point here. Worker: `template/scripts/config/check.sh`.

- versions: no `<version>` placeholder in `.mise.toml` or an app manifest (`pyproject.toml`, `package.json`, `Cargo.toml`, `rust-toolchain.toml`, `go.mod`). A placeholder breaks every toolchain install, so `ctl setup` refuses to install while one remains.
- env: `.env.template` exists, has unique keys and blank values for declared credential names and names containing a `_PASSWORD`, `_KEY` or `_SECRET` segment; every `${VAR}` in `apps/*/config.yaml` appears in that template; no secret literal in those config files; no tracked `config.local.yaml`; no tracked root `.env` or `.env.*` except `.env.template`. Grouping, browser exposure and per-service Docker keys require review.
- layout: no `package.json`, `bun.lock` or `pnpm-workspace.yaml` at the root or directly in `apps/`; no folder under `apps/` that holds a manifest next to child folders with manifests, because that is a workspace. The root half is skipped when `AGENTS.md` records `root-manifest` under `## Exceptions to the standard layout` (`01_layout.md` § Exceptions).
- brief: `CLAUDE.md` is exactly `@AGENTS.md`.
- ladder: the `Gate ladder` row in `AGENTS.md` lists the same rungs, in the same order, as `RUNGS` in `scripts/gate/all.sh`, because the audit reads the row and the gate runs the list.
- lint config: every app ships its linter config beside its manifest (`[tool.ruff]`, `.oxlintrc.json`, `clippy.toml`, `.golangci.yml`), because a linter without its config reports only its defaults.
- compose: no `ports:` in any config (`compose.<name>.yaml`); no `../` in any compose file; every `${NAME}` inside the root .env file names a set key, with no cycle, because these are the values `ctl` hands compose and the apps (`02_env.md` rule 6); `docker compose config` validates every config alone, and every modifier fits at least one config, with the fit list printed because that is what `ctl up` offers, with the env loaded and resolved the way `ctl up` loads it. A modifier whose `MODIFIER_REQUIRES` keys are blank (`+public` before the public origin is uncommented) is skipped and named, the way `ctl up` refuses it. The compose validation is skipped, and says so, when docker is down or the env files are absent.

## `ctl manage` — the break-glass console

The one path to operator identity that does not go through the web. It seeds the first SuperAdmin, resets a password when the admin UI is down, flips a platform setting. Template: `template/scripts/admin/manage.sh`, `template/apps/example-api-python/manager.py`.

| Rule | Why |
|---|---|
| `manage.sh` is a thin forward to `python manager.py "$@"`: inside the running api container when the stack is up (`ctl up`), else on the host through `uv run` (`ctl dev`, where `+expose_db` binds the engines to loopback). Bare `ctl manage` prints ctl's help; anything else reaches argparse, so `ctl manage ops --help` works. | One program, launched where the engines are reachable. The shell layer adds nothing but the env guard and that choice. |
| `manager.py` lives at the backend root, beside `app/`, so it ships in the image. It imports the app's loader and `core/security.py`, never a router. | It is a program, not a domain. Same hashing and connection values as the service; no second copy. |
| It runs without the web auth flow. Access to the host is the boundary. | Nothing else can be: it exists for when auth is broken. So it runs on the host, over SSH, or through `docker compose exec` from the host; no engine port is published for it. |
| Every mutating action writes to `operator_audit` (actor `console`, action, target, outcome). | An unaudited break-glass is a backdoor. |
| Operators are disabled, never deleted. | The audit history must keep its subject. |
| Operator identity is never reachable through public signup or OAuth. The first admin comes from `ctl manage ops create --super`. | The identity plane is separate (`03_routing.md`, case 7). |
| A generated password (`--auto-password`) is printed once, alone on its line, and never logged. | It is a secret in transit. |
| Needs the data core up: `ctl dev`, or `ctl up`. | It talks to the tables directly. |

Adapt `ADMIN_SVC`, `ADMIN_DIR`, `ADMIN_RUNTIME` and the host/container command arrays in `manage.sh`. `auto` selects a running service returned by the current project's Compose query, otherwise the host; `container` refuses host fallback, and `host` selects it explicitly. The container route needs no host manager file or Python environment. `scripts/common/_runtime.sh` preserves argument boundaries and exit status and disables TTY allocation for noninteractive streams. Schema commands continue to use their declared one-shot containers, so Docker mode does not require host Alembic.

Products without an operator plane delete `scripts/admin/` and `manager.py`.

## Without a data core

`DATA_SVCS=()` in `_lib.sh`. `dev`, `up`, `setup`, `status`, `health` skip the engines. `compose.base.yaml` drops the include and the `depends_on`; the `db` config and `scripts/db/` are deleted. `require_env` stays strict only if the apps still read secrets; `status` and `health` point at the app services and their healthchecks instead.

## Without ctl

Every app's README shows how to run it from its own folder. The root README shows the manual path. `ctl` is the sanctioned way, not the only way: raw `docker compose --project-directory . --env-file … -f docker/compose.base.yaml` must keep working beside it, which is why `ctl` never carries state compose does not see.

## When ctl is not enough

`ctl` stays a bash router. Escalate to a compiled orchestrator (Go) only when a verb needs structured state across runs: a plan file, a lock that outlives a shell, a fleet of hosts. Line count alone is not the trigger. The state file is documented and versioned, and the plain compose invariant above still holds.

## The ctl shape, as a check

`ctl check` can prove the router is a router: `ctl` sources `_lib.sh`; every substantive verb is `run`-routed to `scripts/<group>/<name>.sh`; every worker starts with the preamble (`set -euo pipefail`, sources `_lib.sh`) and answers `--help`. A single-file `ctl` with logic inside is a red finding.
