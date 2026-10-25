# ctl — the single entrypoint

`ctl` is a thin bash router at the repo root. It sources `scripts/common/_lib.sh` and executes one worker per verb: `scripts/<group>/<name>.sh`. No logic lives in `ctl` itself. Every verb has `--help`. Nobody types `docker compose -f` by hand.

Template: `template/ctl`, `template/scripts/`.

## Copy and verify

`SKILL.md` § Before anything, step 6, holds the rule: `ctl` and `scripts/` enter a repo only as a copy of `template/`. This section holds the commands and the checks that enforce it. `scripts/template.sh` in the skill folder does the copy and the comparison. Step 4 of the same section says how to find the skill folder on each host. Below, `$skill` is that folder.

| Situation | Command, from the target repo root |
|---|---|
| A bootstrap, or a repo with neither `ctl` nor `scripts/` | `bash "$skill/scripts/template.sh" copy .` |
| A repo that already has `ctl` or `scripts/` | `bash "$skill/scripts/template.sh" copy "$(mktemp -d)"`, then § Adopt an existing repo |
| Any repo, before you change `ctl` or `scripts/`, and after every copy | `bash "$skill/scripts/template.sh" verify .` |

`copy` copies `template/` whole and keeps the file modes. It refuses a target that already has `ctl` or `scripts/`. When any other file it would write already exists, it copies nothing and names each such file, because an overwrite loses the owner's text and a skip leaves a stale file that looks copied.

If the skill folder or its `template/` is unavailable, stop and report the missing path. Ask the user to resolve it, because an access problem does not authorize a replacement.

A worker that stops on a missing tool keeps its `require_tools` call. Install the tool instead (`11_conventions.md` § A missing tool is installed, never coded around).

### Verify

`verify` prints a verdict on its first line, so a short task reads one line and moves on.

| Verdict | Meaning | Next step |
|---|---|---|
| `green` | `ctl` routes through `scripts/common/_lib.sh`, and every shared helper matches this skill's `template-core.sha256` outside its `[ADAPT]` blocks. | Extend the router as § Extending the copied router says. |
| `red — not from the template` | `ctl` does not route through `scripts/common/_lib.sh`. | `SKILL.md` § Before anything, step 5. |
| `red — a copy of another template version` | The helpers match the repo's own manifest but not this skill's. | Offer the update. On the user's yes, copy `scripts/common/` whole from `$skill/template/`, reapply each recorded exception, and run `ctl check`. |
| `red — a template copy older than template-core.sha256` | The repo predates the manifest. | Offer the same update. On the user's yes, also restore or record each local change. |
| `red — a template copy whose shared helpers were changed` | A helper differs from the template. | Ask the user whether to restore it from `$skill/template/scripts/common/` or record it as an exception (below). |

For a template copy, `verify` then lists each file of `ctl` and `scripts/` that is changed, removed or added. Give each one a reason in the report: a row of the delete table in `SKILL.md` § Bootstrapping, an `[ADAPT]` point, a rename, or a new worker. Restore any other change from the template.

### The template core in every repo

`scripts/common/template-core.sha256` lists each shared helper with the SHA-256 of its text. `ctl check` compares the helpers with it as its `template core` rule, so the `check` rung fails a helper edited after the copy, such as a `jq` call replaced by hand-written parsing. `scripts/common/_template-core.sh` holds the comparison, and `verify` runs the same code against the skill's own manifest.

An `[ADAPT]` block is left out of the digest, so a project sets its knobs freely. A block starts at a line that begins with `# [ADAPT]`. It takes the comment lines under that line and the code lines after them, and ends at the next blank line or the next comment line after its code. An indented `# [ADAPT]` comment starts no block, so a knob belongs at column 0, as `ENV_MISSING` in `_lib.sh` is. A change to any other line is recorded as an exception.

To change a helper on purpose, record it in `AGENTS.md` under the existing heading, one line per helper, with the reason:

```markdown
## Exceptions to the standard layout

- `template-core scripts/common/_process.sh`: the GPU worker needs 60 seconds to flush its checkpoint, so the stop grace is 60, not 20.
```

To update the helpers from a newer skill version, copy `scripts/common/` whole, manifest included. Then reapply each recorded exception and run `ctl check`.

### Adopt an existing repo

A repo whose `ctl` is not the template's is adopted only when the user says yes, because adoption renames commands people already type. The result is the template's `ctl` and `scripts/`, the project's own verbs as workers, and no second router.

1. Stage the template: `stage=$(mktemp -d) && bash "$skill/scripts/template.sh" copy "$stage"`.
2. List every old verb: each name in the old router's `case` statement and in its help text. Map each one by the table below. Keep the map, because the report and `AGENTS.md` both need it.

   | Old verb | Becomes |
   |---|---|
   | The same job as a template verb: `setup`, `check`, `status`, `dev`, `test`, `gate`, `up`, `build` and the rest of § Verbs | That template verb. Port only its project-specific commands into the worker's `[ADAPT]` points. |
   | A project job with no template verb, such as `train` or `notebook` | A new worker `scripts/<group>/<name>.sh` with the preamble and `--help`, plus one `run` line and one help row in `ctl` (§ Extending the copied router). |
   | A second name for a job that already has one, such as `model-gate` beside `gate` | Deleted. The template name stays. |
   | A verb that only prints that its work moved or ended | Deleted. |

3. Move the logic out of the old router. An exported variable becomes a key in `.env.template`, or a line in the one worker that needs it. A loop over rungs is `ctl gate`. A script under `scripts/` in another language moves into the app that owns it, or is rewritten in Bash or TypeScript (§ Scripting languages).
4. Delete the old `ctl` and `scripts/`, because git history keeps them and a second router is drift. Move `ctl` and `scripts/` from the stage into the repo. From the stage, take what the kept workers need: `.mise.toml` and `.env.template`, merged by hand with the repo's values, and `docker/` when the repo runs containers. Then apply the delete table in `SKILL.md` § Bootstrapping for what the repo does not have. A repo with no engines follows § Without a data core.
5. Add the mapped workers. Record in `AGENTS.md` each old verb with what it became, so people find their commands, and each exception.
6. Run `./ctl setup env`, `./ctl check`, `./ctl setup`, `./ctl gate`, then `verify`. Report the verb map, the verdict and each exit code.

## Extending the copied router

The verb table below is the floor, not the ceiling. A project adds the verbs its work needs (`ctl train`, `ctl sqlx-prepare`, `ctl mobile-api-codegen`, `ctl seed`, `ctl deploy`) the same way every existing verb is built: one worker at `scripts/<group>/<name>.sh` with the preamble, `--help`, and one `run <group>/<name>` line in `ctl`. New groups are fine (`scripts/ml/`, `scripts/admin/`). Two rules hold: logic never lives in `ctl` itself, and every added verb has a help row in `ctl`, so `ctl --help` shows it. Verbs that stop being used are deleted, not left as residue.

A worker prints its help with `print_help`, and a help row in `ctl` uses `row`. Both pass through `help_wrap` in `_lib.sh`. In a terminal, it folds each line wider than the window at a space, and a row's text continues under the row's text column. A pipe gets the text as written, one line per row, so `grep` and the tests read it whole. Separate a row's term from its text by two or more spaces, because that gap is how `help_wrap` finds the column. A help printed with `cat` or `echo` gets neither behavior.

## Scripting languages

Use Bash for CTL entrypoints, command routing, process ownership and locks.
Use TypeScript with Bun for structured coordination, such as a multi-step Rust build.
Keep repository-owned CTL automation under `scripts/` in these two languages so
projects share one scripting toolchain. Do not add Python, Go or other scripting
implementations there. Calling an application's own Python manager, Rust compiler
or database tool is allowed; those commands belong to the application or tool.
Use Bun's test runner for new CTL regression tests. Preserve meaningful lifecycle
coverage when converting an existing test suite; changing language is not a reason
to remove a failure check. This rule does not change application implementation or
test languages. Existing marketplace authoring tests outside the shipped template
are a separate suite and are not installed by CTL.

## Verbs

| Group | Verb | Does |
|---|---|---|
| Development | `dev [app…] [--detach] [--all] [--no-core] [--nqa] [--dry-run]` | Reuse the running data core or start it, apply migrations, then run the apps on the host with reload. Apps run on the host because a debugger attaches and file events are native; source is never bind-mounted into a dev container. A stopped core: in a terminal `dev` asks first, and Enter means yes; `--all`, `--nqa` and no terminal start it without asking. `--detach`: logs and ownership records below the configured `LOGS_DIR`. `--no-core`: skip the data core. `--nqa`: skip the app picker. `dev` guards and instructs (`run ctl setup env`); it never edits config mid-launch. § The data core below. |
| | `dev db [--detach] [--dry-run]`, `dev db stop [--dry-run]` | The data core alone: start it detached through the reserved `dev` preset and migrate, or stop it. `dev db stop` refuses while a dev app or an app container runs. |
| | `dev stop [--all] [--nqa] [--dry-run]` | Stop the host processes `ctl` started for this checkout and keep the data core. In a terminal it asks whether to stop the core too, and Enter keeps it. `--all` runs `ctl stop`. |
| | `ps [--list \| kill [port…]]` | Everything running across three planes: host processes, frozen builds, containers. Attach or kill, plane-aware. |
| | `stop [--dry-run]` | Stop this project's recorded host groups and frozen servers, then its app containers, then the data core. Keep containers, data and volumes. No prompts. |
| Containers | `up [--config c] [+modifier…] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list]` | A stack shape (`compose.<config>.yaml`, `base` by default) plus modifiers, every service or a subset. In a terminal: pick a config → pick the modifiers that fit → pick services (all preselected) → plan → confirm. Flags skip their prompt. No TTY: the plan prints and the run refuses without `-y`; `--nqa -y` is the scripted form. Compose orders engines, schema one-shots, apps by itself. `08a_ctl_docker.md`. |
| | `up preset [<name>] [-y]`, `up preset --list`, `up set-preset [<name>]` | A saved `up` line from `docker/presets.yaml`: run one with no prompts, list them, or walk the pickers and save. `08a_ctl_docker.md` § 4. |
| | `down`, `restart`, `logs`, `exec`, `shell` | Compose passthroughs against the `base` file. `down` never uses `-v`: state lives in `data/`. |
| | `build [app…\|cli]` | Compose build. Build args are prefixes interpolated from `.env`. `cli`: the Go binary. |
| | `clean [-y]` | Down plus caches. `data/` untouched. |
| | `clean rust [--dry-run]` | Remove local `target/debug` directories beside discovered Rust `Cargo.toml` files under `apps/` and the managed Rust app/controller logs in `LOGS_DIR/dev/`. First stop the recorded Rust dev processes. The Rust app names are declared in `scripts/dev/_apps.sh`; adapt them when renaming or adding a Rust app. Keep `target/release`, lockfiles, data, other app logs and external Cargo caches. External `CARGO_TARGET_DIR` values are outside this command. |
| | `health [svc…]` | One-shot health table. |
| Database | `db migrate [up\|new "<msg>"\|status\|check]` | Flyway applies versioned PostgreSQL SQL. The Compose migration service runs Flyway inside Docker. `new` writes a file without connecting. `check` verifies currency. Production orders its migration one-shot before apps. |
| | `db shell <engine>` | psql, redis-cli, cypher-shell with `.env` credentials. |
| | `db backup`, `db restore <dir>` | Dump to `${BACKUP_DIR}/<timestamp>/`; load back. Restore validates the PostgreSQL archive before mutation and refuses while configured app containers or recorded host processes run. |
| Administration | `manage ops <list\|create\|disable\|enable\|reset-password\|lockout>` | Operator accounts, without the web auth flow. Below. |
| | `manage settings <list\|get\|set>` | Platform settings, value parsed as JSON. |
| Test | `test [app…\|e2e]` | Each app's own suite, under the TESTING settings in `.env`. A suite marked `db` gets its own copy of a throwaway, migrated PostgreSQL. `e2e`: a throwaway stack. See `10c_dynamic-tests.md`. |
| | `build save\|start\|clean` | Frozen test builds under `${LOGS_DIR}/test_build/`. `09_production.md`. |
| Gates | `gate [--changed \| --delta <base> \| --all \| all] [--dry-run] [-q]` | The ladder: lint → typecheck → dead → audit → test → check → build → e2e, trimmed to the rungs `AGENTS.md` lists. The floor is `lint typecheck test check`. Plain `gate` checks what the uncommitted changes reach, `--delta <base>` the changes since a branch, a commit or a date-time, and `--all` or `all` everything. `--dry-run` prints the selection and runs nothing; it does not go with `--all`. `check` always runs, and the run names every rung and app it skipped. Stops at the first red, names every rung not reached. A green run records the tree it passed, and a later run on the same tree and base prints `already green` and runs nothing; `--rerun` runs it again. One run per user at a time, under a memory lid. `10b_static-checks.md`, `10d_test-speed-and-resources.md`. |
| | `gate [static\|dynamic] [mode] [--cpus LIST] [--build-jobs N] [--memory SIZE]` | Override the TESTING settings in `.env` for one ladder run. A rung run by name takes none of these flags and reads the shell and `.env`. `10d_test-speed-and-resources.md`. |
| | `gate static\|dynamic [-q]` | The listed rungs that read the code, or the ones that run it. Ladder order kept. |
| | `gate <rung> [-q]` | One rung, on the whole repo unless apps are named. `gate lint [app…] [--staged]` and `gate typecheck [app…]` take apps; the others take none. |
| | `gate clones\|fuzz\|perf` | By name. Never in the ladder. |
| Releases | `merge <branch> [--minor[=PART]] [--major[=PART]] [--dry-run]` | The one way a branch lands on the default branch. In the worktree that holds it: merge the default branch in, set the version of each part the branch changed (`VERSION_PARTS` in `scripts/release/versions.sh`) and commit them, run `gate --delta <default>` once with `CTL_MERGE=1`, then fast-forward the main tree. Never pushes. `15_releases.md`. |
| Configuration | `setup [--remove-unlisted]` | The env step of `setup env`, then toolchains installed and activated, then source-package dependencies and hooks installed. |
| | `setup env [--remove-unlisted]` | The env step alone: `.env` created from its template or rebuilt in its shape with every value kept, declared local credentials generated and checked, storage folders created under `BASE_DIR`. Installs nothing. A key the template lacks is removed only on a yes in a terminal or with `--remove-unlisted`. `02_env.md` § Setting up `.env`. |
| | `check` | The repo contract. Below. |
| | `status` | Read-only doctor: env, runtimes, deps, docker, health, stack. Never dies. |
| Worktrees | `worktree create <name> [--from <ref>]` | Puts a free slot, a git worktree at `.worktrees/slot-<n>` whose builds stay warm, on branch `<name>`, and prints the slot's path. A slot's first use writes its `.env` with every port + 100 × n. `13_worktree.md`. |
| | `worktree list` | Each slot: name or free, clean or dirty, merged into the main tree, build size, last use. |
| | `worktree remove <name>` | Frees the slot once the worktree is clean, not busy, and merged into the main tree. Keeps the branch and the builds. No force option. |
| | `worktree trim [--days N] [--dry-run]` | Deletes Cargo outputs no build used for N days, in every idle slot. `create` and `remove` run it weekly. |

## The compose model

`08a_ctl_docker.md` is the home of this. In one line: a **config** (`compose.<name>.yaml`, one stack shape, `base` is prod and the default) plus **modifiers** (`compose.m.<name>.yaml`, only the ones compose accepts on that config) plus a **service subset** (only those and their `depends_on` chain build and run), saved as a **preset** (`docker/presets.yaml`, one `ctl up` line per name), with **`include:`** as the way one config borrows another file. A config never publishes a port. The plan is the real `docker compose config` merge.

Constants that hold everywhere: root-relative paths with `--project-directory <root>`; the root .env file passed with `--env-file`, Compose uses the explicitly selected file (compose ≥ 2.24); no profiles, no bare `compose.yaml`, no `compose.override.yaml`; bind mounts under `${DATA_DIR}`, never named volumes; internal ports fixed (`api:8000`), only published host ports vary.

**The docker guard runs first, by name.** Every docker verb calls `require_docker` before its first compose call. It tells three faults apart: not installed, engine not running, compose plugin missing. Compose itself reports a dead engine as a config error, which is how an earlier `up.sh` printed "invalid modifier combination" for "Docker is not running". `ctl status` shows the same three states without dying.

The `scripts/` groups are `common config dev container db admin test gate worktree`. A gate rung never holds logic: it calls the same worker its dev verb calls (`gate/test.sh` → `test/test.sh`); lint and typecheck have no separate dev verb, the rung is the worker, so the gate and the loop cannot drift.

## Setup and tool availability

`ctl setup` runs two steps in one worker, `scripts/config/setup.sh`. The env step writes `.env`, its credentials and the storage folders. `02_env.md` § Setting up `.env` owns what it does. The install step installs the toolchains, the source dependencies and the hooks, as the rest of this section describes. `ctl setup env` runs the env step through the same function and stops, so it needs no toolchain. Use it when only `.env` must change, before the versions are resolved, and on a host that runs prebuilt images. A failed env step stops `ctl setup` before any install.

`scripts/config/_discovery.sh` discovers source manifests below `apps/`, including nested packages, to a maximum depth of 12. It prunes dependency, build, cache, vendor and generated directories and does not follow directory symlinks, so installing a source package cannot recurse into its installed dependencies. Cargo identifies the owning workspace before fetching; one workspace is fetched once, and an excluded independent crate keeps its own fetch. Setup fails on discovery or dependency-install errors. The conformance version scan uses the same source discovery.

`scripts/common/_tools.sh` installs declared mise toolchains during setup, then activates them in the same invocation. It evaluates only the shell environment emitted by mise, never the contents of `.env`. Activation preserves application environment overrides while selecting tool paths. `require_tools` activates without installing and verifies that each requested executable runs. A selected app asks only for its own runtime; missing required tools are errors, not successful skips.

The Rust example declares Bun, Cargo and Watchexec in `.mise.toml` because its
TypeScript coordinator uses those tools. Resolve the watcher version during setup.
Remove the watcher declaration when removing the Rust example.

## Development readiness and ownership

Every normal `ctl dev` launch runs `scripts/config/_validate-env.sh` before installing
dependencies or starting services, because stale settings should fail at the entrypoint.
It checks template key coverage, duplicate or malformed assignments, required credentials,
nonempty defaults, placeholders, ports, URL shape and route prefixes. Blank template values
remain optional unless declared credentials require them. Add domain-specific checks here
when adapting the template; these format checks do not prove remote connectivity.
Missing keys direct the user to `ctl setup env`; validation never rewrites supplied values.

Then call the shared discovery/install helper with `--locked`, so package managers
synchronize installed dependencies directly without a custom freshness database.
Use `uv sync --locked`, `bun install --frozen-lockfile` and `cargo fetch --locked`.
Missing or stale lockfiles fail with an instruction to update them explicitly.
For Go sources, `go list -mod=readonly -deps ./...` checks the module graph; Go can
still add missing checksum entries to `go.sum`. Setup uses the same helper without
locked mode to prepare or update dependencies. Toolchain installation and activation
run before synchronization. Failure in any step prevents launch. `--no-core` skips
the data stack only; help and dry-run skip installation. Existing credential rules
live in `02_env.md`.

Adapt `scripts/dev/_apps.sh`: each app declares its command, required tools, readiness probe and timeout. The shipped API and engine probes call their prefixed `/ready` endpoint; frontend probes exercise HTTP. Change a probe when the app needs a stronger condition. A listening port alone never permits a successful skip: a pre-existing listener must pass the same probe, and it is left running if this launch fails.

`scripts/common/_process.sh` installs cleanup before launch and starts each owned command in its own process group. Failed startup, bounded probe timeout, early exit and interruption return nonzero and clean up owned groups, including normal descendants. Detached success requires all selected apps ready; foreground mode monitors owned processes and reports unexpected exits. Readiness is a point-in-time check, not a promise that a dependency stays available.

Ownership records live in `LOGS_DIR/run/<name>.process/`, including a PID and its process-start identity; output lives in `LOGS_DIR/dev/<name>.log`. Identity checks prevent a reused PID from being treated as the old process. Attach, stop and frozen-build commands use the same configured paths. The host-process implementation requires Linux or WSL, Bash, `/proc`, `setsid` and GNU coreutils. Programs that deliberately escape their process group need a project-specific supervisor.

Frontend dev servers own routing; there is no development proxy container.

### The data core

The data core is the `DATA_SVCS` engines that the reserved `dev` preset in `docker/presets.yaml` starts: `--config base +expose_db --services postgres,redis,neo4j`, each engine bound to loopback. It runs detached and outlives the host apps, so an app restart never waits for a database. `scripts/dev/_data-core.sh` holds the steps, and `ctl dev` and `ctl dev db` share it, so the two commands cannot drift. When you adapt the preset, publish every `DATA_SVCS` engine on loopback with a `ports:` entry in `docker/compose.m.expose_db.yaml`, because `ctl dev` refuses to reuse an engine without a host port.

| The core when `ctl dev` starts | What `ctl dev` does | Why |
|---|---|---|
| Every engine runs and passes its healthcheck | Reuse it as it is. Never start, recreate or rebuild it. | A restart drops every open connection and costs the engines' start time. |
| An engine runs but publishes no host port | Refuse, and point at `ctl stop`. | Another stack shape, such as `ctl up`, started it. A host app would reach whatever else holds that port. |
| An engine is down, in a terminal | Ask `The database is not running. Start it with 'ctl dev db --detach'`. Enter means yes. Any other answer stops the launch and names that command. | A start binds the engine ports and takes memory, so a person at the terminal decides. |
| An engine is down, with `--all`, `--nqa` or no terminal | Start it without asking. | A script or an agent has nobody to answer, and the apps cannot run without the core. |

The start runs `ctl up preset dev --nqa -y --no-build`, which builds no engine image and returns only after every engine passes its healthcheck within the bounded start budget. After the reuse or the start, `ctl dev` runs `ctl db migrate up` every time, because a running core can still lack this checkout's newest migration. A migration failure stops the launch before any app starts. An empty `SCHEMA_SVCS` in `_lib.sh` means the project has no schema step, and `ctl dev` skips it. The migration step builds the migration image from the layer cache, because that image carries the SQL. An unchanged checkout rebuilds nothing. The `dev` preset holds no schema one-shot, because the schema step always runs through `ctl db migrate`.

Ctrl-C, `ctl dev stop` and a failed launch stop only host processes, and the data core keeps running. `ctl dev db stop`, `ctl dev stop --all` and `ctl stop` stop it. § `ctl stop` below shows how the three divide the work. A change to an engine in `docker/`, or to an engine port in `.env`, takes effect at the next core start: run `ctl dev db stop`, then `ctl dev`.

### Controllers and Rust development

`scripts/dev/_controllers.sh` maps selected apps to managed controllers. The shipped
Rust example selects one engine watcher. Return no names for apps that need none.
`scripts/common/_controller.sh` checks process ownership and readiness.
`scripts/common/_controller-lock.sh` supplies the lifetime kernel lock. Reuse these
helpers so a second launch cannot start a competing controller. Reused controllers
remain owned by their original launcher; a later failed launch cannot stop them.
Refuse a held lock whose owner cannot be verified. Recover abandoned metadata only
under the lock. Owned controllers participate in `ctl stop` and startup cleanup.

`scripts/dev/rust-watch.ts` is the runnable Rust watcher example. Adapt
`scripts/dev/rust-watch.config.ts` to declare source paths and command argument
arrays. Watchexec detects edits and debounces them. Bun runs the declared commands
in order; a failing command prevents later commands from running. The native
example uses Cargo's development build through `cargo run`. CTL starts this watcher
once through the controller hooks and reuses its ready listener at the app step.
Do not start another Cargo watcher for the same engine.

For WASM, add the package's development build command before the native run command.
Include that package's source and manifest paths. The development profile still
requires compilation; watching automates compilation rather than interpreting Rust.
The simple example restarts the development cycle on edits and does not preserve
in-memory application state. A stateful document host needs project-specific safe
activation and rollback, as described in `06_backend.md` under Watching and activation.
Keep that coordinator in TypeScript. Keep ownership and locking in the shared shell
helpers. Production builds explicitly select release profiles and do not run this watcher.

## `ctl stop` — project-wide shutdown

Worker: `template/scripts/dev/stop.sh`. Shared stop helper: `template/scripts/dev/_stop.sh`, which `ctl stop`, `ctl dev stop` and `ctl dev db stop` all call, so the three apply one set of ownership and ordering rules. Lifecycle helper: `template/scripts/common/_process.sh`.

| Command | Host processes | App containers | Data core |
|---|---|---|---|
| `ctl stop`, and `ctl dev stop --all`, which runs it | stop | stop | stop, after the app containers |
| `ctl dev stop` | stop | keep | keep. In a terminal, ask; Enter keeps it |
| `ctl dev db stop` | refuse while one runs | refuse while one runs | stop |

`ctl dev db stop` refuses rather than stopping the writers itself, because the user asked to stop the database, not the apps. It counts a host process record it cannot verify as running. Its `--dry-run` refuses the same way, so the preview matches the real run.

Bare `ctl stop` stops foreground and detached managed groups from the configured `LOGS_DIR/run`, including watchers and frozen-build servers. It never selects host processes by port. `--dry-run` lists targets without signals, record cleanup or container changes; Docker queries still run.

Each new record stores the project root, PID and start identity. A live legacy record with a start identity needs a working directory inside this project to establish ownership. Live PID-only records and foreign records fail closed, because they cannot safely identify this project's process. Stale records are cleaned; reused PIDs are not signalled. Keep `LOGS_DIR` project-specific. Processes deliberately detached from the managed group need their own supervisor cleanup.

Shutdown sends TERM and allows up to 20 seconds per group for watcher cleanup before verified KILL. `PROCESS_STOP_TIMEOUT` may set a positive integer grace in seconds. Remaining live groups or signal failures retain their records and return nonzero. A host failure leaves containers running, so databases cannot disappear underneath an unresolved writer.

Docker targets must match both the resolved Compose project name and the exact project working-directory label. This includes orphaned services from other stack configurations of the same project. Non-data containers stop before the `DATA_SVCS` engines. Update that existing data-service list when adapting the stack, because it defines shutdown order. Failed writer shutdown leaves engines running. Docker checks and stop calls are bounded; missing or unreachable Docker returns nonzero after host cleanup. Repeating a successful stop is safe. Do not launch new project workloads concurrently with shutdown; this command is not a project-wide launch lock.

## `ctl check` — the repo contract

Runs directly, and as the `check` rung of the ladder. It runs every rule, prints every failure with its file, and exits 0 only when all of them passed, because a check that stops at the first red hides the second one and a check that prints an ok line under a failure teaches the reader to skip the output. This list is the one home of what it proves; `02_env.md`, `01_layout.md` and `11_conventions.md` point here. Worker: `template/scripts/config/check.sh`.

- versions: no `<version>` placeholder in `.mise.toml` or an app manifest (`pyproject.toml`, `package.json`, `Cargo.toml`, `rust-toolchain.toml`, `go.mod`). A placeholder breaks every toolchain install, so `ctl setup` refuses to install while one remains.
- env: `.env.template` exists, has unique keys and blank values for declared credential names and names containing a `_PASSWORD`, `_KEY` or `_SECRET` segment; every `${VAR}` in `apps/*/config.yaml` appears in that template; no secret literal in those config files; no tracked `config.local.yaml`; no tracked root `.env` or `.env.*` except `.env.template`. Grouping, browser exposure and per-service Docker keys require review.
- storage: `.env.template` derives a declared `DATA_DIR` and `LOGS_DIR` from `${BASE_DIR}`, and `BACKUP_DIR` from `${LOGS_DIR}` or `${BASE_DIR}`, each below the line it reads, because Compose resolves a reference inside the env file only to an earlier line. In `.env`, no storage path written relative resolves outside `BASE_DIR`, because a relative path stays at the repo root when `BASE_DIR` moves; an absolute path counts as deliberate (`02_env.md` § Host storage paths).
- layout: no `package.json`, `bun.lock` or `pnpm-workspace.yaml` at the root or directly in `apps/`; no folder under `apps/` that holds a manifest next to child folders with manifests, because that is a workspace. The root half is skipped when `AGENTS.md` records `root-manifest` under `## Exceptions to the standard layout` (`01_layout.md` § Exceptions).
- brief: `AGENTS.md` exists at the repo root; every `AGENTS.md` has a `CLAUDE.md` beside it that is a plain file holding exactly `@AGENTS.md`, and every `CLAUDE.md` has an `AGENTS.md` beside it; each brief is under 200 lines, all of them together at most 32 KiB, and none holds a `YYYY-MM-DD` date, because a brief loads every session and holds current facts only (`11_conventions.md` § The agent brief).
- template core: every shared helper in `scripts/common/` matches `scripts/common/template-core.sha256` outside its `[ADAPT]` blocks, unless `AGENTS.md` records `template-core <path>` under `## Exceptions to the standard layout` (§ Copy and verify).
- ladder: the `Gate ladder` row in `AGENTS.md` lists the same rungs, in the same order, as `RUNGS` in `scripts/gate/all.sh`, because the audit reads the row and the gate runs the list.
- lint config: every app ships its linter config beside its manifest (`[tool.ruff]`, `.oxlintrc.json`, `clippy.toml`, `.golangci.yml`), because a linter without its config reports only its defaults.
- source size, a warning: each source file in `ctl`, `apps/` or `scripts/` with more than 500 lines is named, because a file that long often holds more than one job (`11_conventions.md` § Caps and extraction). It never fails the check, because a long file can be the right shape. Generated files, `.d.ts` files and SQL do not count. A file that stays long on purpose is recorded as `size-cap <path>` under `## Exceptions to the standard layout`, which silences it.
- doc pointers: no file in `ctl`, `apps/`, `scripts/` or `docker/` other than Markdown names a skill page (`references/NN_*.md`) or a tracker issue (`data/tasks/<date>-…`), because documentation points at code and never the reverse. A file that names one on purpose is recorded as `doc-pointer <path>`.
- migrations: no file in `apps/database/postgres/migrations/` that is on the default branch is changed or deleted, in commits or in the working tree, because a database has applied it and Flyway refuses a changed history. A change is a new migration.
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

Adapt `ADMIN_SVC`, `ADMIN_DIR`, `ADMIN_RUNTIME` and the host/container command arrays in `manage.sh`. `auto` selects a running service returned by the current project's Compose query, otherwise the host; `container` refuses host fallback, and `host` selects it explicitly. The container route needs no host manager file or Python environment. `scripts/common/_runtime.sh` preserves argument boundaries and exit status and disables TTY allocation for noninteractive streams. Schema commands continue to use their declared one-shot containers, so Docker mode does not require a host migration runtime.

Products without an operator plane delete `scripts/admin/` and `manager.py`.

## Without a data core

Empty the default on the `DATA_SVCS_STR` line in `_lib.sh`, so the line ends in `${DATA_SVCS-}}"`, and empty the `SCHEMA_SVCS_STR` line's default the same way. Edit those lines, not the arrays, because the `read` line below each one fills its array from it, in `ctl` and again in every worker. Remove unused engines, migration jobs and their `depends_on` entries from `compose.base.yaml`; remove the dev preset and `scripts/db/`. `dev`, `setup` and `status` skip the engines. `require_env` stays strict only if the apps still read secrets; `status` and `health` point at the app services and their healthchecks instead.

## Without ctl

Every app's README shows how to run it from its own folder. The root README shows the manual path. `ctl` is the sanctioned way, not the only way: raw `docker compose --project-directory . --env-file … -f docker/compose.base.yaml` must keep working beside it, which is why `ctl` never carries state compose does not see.

## When ctl is not enough

`ctl` stays a Bash router. Put structured coordination in a TypeScript helper under the owning script group, following Scripting languages above. Document any persisted state format so commands can validate it. The plain Compose invariant above still holds.

## The ctl shape, as a check

`ctl check` can prove the router is a router: `ctl` sources `_lib.sh`; every substantive verb is `run`-routed to `scripts/<group>/<name>.sh`; every worker starts with the preamble (`set -euo pipefail`, sources `_lib.sh`) and answers `--help`. A single-file `ctl` with logic inside is a red finding.
