# Changelog

## 0.22.0

- Every deploy writes a transcript. A deploy is a `ctl up` whose `TAG` is set and that `image_tag_local` does not call local. It writes its whole output, stdout and stderr, to `LOGS_DIR/deploy/<YYYYmmdd-HHMMSS>-<tag>.log`, with the UTC start and the resolved tag. No flag turns it on. It starts once the plan is settled, so `--dry-run` and `--list` write nothing, and it runs to the end: build, activation, readiness, retention and any error. An EXIT trap writes the last line, `result: ok` or `result: failed (exit N)`. The terminal still shows the output with its colours, the transcript gets it without colour codes, and stderr stays stderr. With `-a`, the container log stream after startup goes to the terminal only. A local run writes no transcript. Server deploys used to run as `nohup ./ctl up … > ~/<name>.log 2>&1 &`, which kept no result and no record.
- `ctl up … -y --background` runs the same line detached from the terminal, in its own session with stdin from `/dev/null`, and returns at once with the transcript's path and `ctl up status -f`. It always writes a transcript, even for a local tag. It needs `-y`, implies `--nqa`, and refuses `-a`, `--dry-run`, `--list` and `set-preset`.
- `ctl up status [-f]` reads the newest transcript. It prints the file, the tag, the start, `DATA_DIR/deployed-commit`, the state and the last lines. The state is running, succeeded, failed (exit N), or interrupted, which means no result line and no process left. It exits 0 when the run succeeded or still runs, and 1 otherwise. `-f` follows a running run to its end and exits with its result.
- Only one deploy runs at a time. A deploy or a background run holds the process record `LOGS_DIR/run/up.process`, through the `_process.sh` helpers, so a second one refuses, and `ctl db restore` and `ctl dev db stop` wait for it. `process_claim` records a foreground shell; `process_stale` is the one test of a record whose process ended, and `process_start` uses it too, so a live claim is never removed. `process_start` writes to `PROCESS_LOG` when that is set.
- A deploy stops before the plan when the current user cannot write `LOGS_DIR/deploy`, `LOGS_DIR/run` or `DATA_DIR`, naming the folder and the `chown` that fixes it. On hs-nuc a root-owned `DATA_DIR` and `LOGS_DIR` went unnoticed until the deploy reached its record write, after the build.
- `ctl check` has a new storage rule: with `.env`, the `DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` folders exist and the current user can write each. A failure names the `chown`. `storage_dir_writable` in `_paths.sh` is the one check, for `ctl check` and the deploy.
- The new code lives in `scripts/common/_transcript.sh`, which `up.sh` sources. `_compose_start.sh` sends the `-a` log stream to the terminal only. `ctl --help` lists the two new forms.
- `08_ctl.md` gains § Deploy transcripts and the two verbs. `09_production.md` § The deploy runs `ctl up preset public -y --background` over SSH and checks it with `ctl up status`. It says where transcripts live and that the deploy user must own the storage folders, which `ctl check` proves; § The host and the checklist say the same. `01_layout.md` and `02_env.md` list `deploy/` under `LOGS_DIR`.
- `test_transcript.py` covers each rule. The `test_config.py` check fixtures now create the storage folders, as `ctl setup env` does, and the `test_deploy.py` repository ignores `logs/`, as the template does.

## 0.21.1

- Image retention counts and removes only deploy tags. A local tag (`dev`, `dev-<name>`, `latest`) is neither counted nor removed, so a deploy on a machine with worktree slots no longer deletes the slots' images. One shared rule, `image_tag_local` in `_images.sh`, decides a local build for both the rollback guard and retention. A pinned `TAG=latest` is now a local build too.
- `ctl db migrate up` checks that the tag allows a build before it moves the deploy record. A refused build used to move the record even though nothing migrated.
- The deploy record follows the data. `ctl db backup` copies `DATA_DIR/deployed-commit` into the backup. `ctl db restore` puts it back, so the commit the backup's data matches may deploy again. Before this, a restore followed by a deploy of that commit was refused as a rollback. A backup without a record leaves the current record, so only a deploy at or ahead of it may start. A backup record that holds no commit stops the restore before any engine changes. `deploy_commit_valid` is the one check of a record's text.

## 0.21.0

- Rollbacks are off by default, and never cross a migration. `.env.template` gains `ROLLBACK=off` in the Images group. `off`, also what an unset or empty value means, refuses every rollback. `on` allows one only when no file under `MIGRATION_PATHS` differs between the two commits. `MIGRATION_PATHS` is an `[ADAPT]` knob in `_lib.sh`, `apps/database` by default. Any other value is an error, and `ctl check` names it.
- A deploy is a `ctl up` with `TAG=auto` or a pinned tag. Each deployment keeps a record, `DATA_DIR/deployed-commit`, with the full commit of the last deploy that reached activation. `ctl` writes it just before activation, not after readiness, because the migrate one-shot may change the data even when a later service fails. A deploy whose commit is not ahead of the record is a rollback, and the guard runs before anything starts, with or without `--no-build`. A pinned tag that names no commit is refused, and so is a record whose commit the checkout lacks; the message names the record file. `ctl db migrate up` passes the same guard and writes the same record. `dev`, `dev-<name>` (a slot's `dev-slot-<n>`), `none` and an unset `TAG` are local builds: no guard, no record.
- After a deploy is ready, `ctl` keeps the 2 newest tags of each image it builds, by creation time, and removes the rest with `docker image rm`. `IMAGE_KEEP` is the `[ADAPT]` knob. It never removes an image a container uses, never lists a repository it does not build, and turns a docker error into a warning, never a failed deploy. The output names what it removed.
- Images are built from source on the server and never pulled. Every built service in `compose.base.yaml` says `pull_policy: never`, so a missing image is an error, never a download from `REGISTRY`; third-party images keep compose's default. `ctl check` fails a built service without it.
- `09_production.md` § The deploy says the server builds every image from a full clone, with no registry. It adds recovery forward and the retention step, and its checklist drops the rollback line. The `.env.template` notes for `REGISTRY` and `TAG` say the same, and the `REGISTRY` placeholder is `<product>` instead of `ghcr.io/<org>`, because no registry is involved. `08_ctl.md` and `02_env.md` no longer describe a host that runs prebuilt images, and § Multi-stack no longer pushes images between repos.
- The image tag functions and the new deploy steps live in a new shared helper, `scripts/common/_images.sh`, which `_lib.sh` sources, so `_lib.sh` stays under the 500 lines `ctl check` warns at. The two new knobs stay in `_lib.sh` with the others.
- `test_deploy.py` covers each rule; the shim in `test_up_lifecycle.py` answers `docker image` and `docker ps` calls.

## 0.20.1

- `scripts/db/migrate.sh` stops when its migrate image build is refused, such as a `TAG=auto` build from a checkout with uncommitted changes. `ctl db migrate check` runs that build inside `$(…)`, where bash does not apply `set -e`, so the refusal used to fall through to `docker compose run`, which builds a missing image by itself.

## 0.20.0

- `TAG` takes four forms, and `ctl` resolves it once per run, in `_lib.sh`, for every compose call: `dev` for local builds, `auto` for the checkout's commit (`git rev-parse --short=8 HEAD`), `none` for images called `latest`, and any other valid Docker tag used as written. `.env.template` keeps `TAG=dev` and lists the four forms beside it. `09_production.md` § The deploy recommends `auto` for production, because a tag typed by hand gets forgotten: the build then reuses the last deploy's name, and the previous images lose theirs, so no rollback image is left.
- A build with `TAG=auto` from a checkout with uncommitted changes, tracked or untracked and not ignored, is refused, because its images would carry a commit's name without matching it. `ctl up`, `ctl build`, `ctl db migrate` and the test database build through one check; `--no-build` starts the images that exist without it. `auto` outside a git checkout, and a tag Docker would refuse, stop every verb with the fix named. `ctl check` checks `TAG` too.
- A value set in the shell still wins over `.env`, so `TAG=<old commit> ctl up preset public --no-build` rolls back. A nested `ctl` resolves `auto` again at its own commit. An unset `TAG` is left alone, for a repo whose compose files name no tag.
- The `ctl up` plan prints the tag, such as `tag  auto → f5744bff`, and its reproduce lines start with `TAG=<commit>` when `ctl` resolved one.
- A slot's `.env` gets `TAG=dev-slot-<n>` whatever the main tree's `TAG` is, so a slot never takes a production name.
- `test_image_tag.py` covers each form and each refusal; `worktree.test.ts` covers a slot made from an `auto` or a pinned main tree.

## 0.19.0

- The main-tree guard is on by default. `ctl dev`, `test`, `gate` and `build` refuse in the main checkout and point at `ctl worktree create`, because the main tree's build folders fall behind while work happens in slots: on Studio, one gate there took 836 s, where a warm slot's took 340 s, and Cargo recompiled third-party crates. `.env.template` ships `WORKTREE_ONLY=1`, and an empty value or a missing key means on too. `0` turns it off.
- Two checkouts with no slot run with `WORKTREE_ONLY=0`: CI (`10b_static-checks.md`) and a bootstrap's first gate on the uncommitted copy (`SKILL.md`, step 8). `ctl merge` needs nothing, because it runs its gate in the branch's slot.
- `13_worktree.md` § The main-tree guard gives the reasons and the exceptions. The gate test fixture, a main checkout with no slots as a CI clone is, runs with the guard off; `worktree-safety.test.ts` tests it on, off, empty and in the shell.

## 0.18.0

- `ctl worktree` makes no name links. Git's worktree list is the one record of which slot holds which branch, so `.worktrees/<branch> -> slot-<n>` only repeated it, and two records of one fact could disagree. `create <branch>` prints the slot's path, `.worktrees/slot-<n>`; `remove <branch>` finds the slot through git; `list` shows each slot's branch. The state rule shrinks to one line: every `slot-<n>` folder is a worktree git lists. A branch may now start with `slot-`, and a name no longer has to fit beside other links.
- `create`, `remove` and `trim` delete a name link an older `ctl` made, and the folders it leaves empty; `list` names one. A link that points anywhere else is left alone.
- `13_worktree.md` § The pool's one record replaces § Names are links to slots; the layout, the commands and the template brief follow. `CTL_ROOT` stays the physical path, for a checkout a person reaches through a symlink of their own.

## 0.17.0

- `ctl test` runs every suite marked `db` against a throwaway PostgreSQL of its own, never the dev data core (`scripts/test/_test-database.sh`). The server runs the compose postgres image on tmpfs with `fsync=off`, on a loopback port Docker picks. The run migrates `test_template` once with the project's migration image, and each `db` suite gets its own copy through `CREATE DATABASE … TEMPLATE`, read from `DATABASE_URL`, `TEST_DATABASE_URL` and the `POSTGRES_*` parts. A caller's `TEST_DATABASE_URL`, such as a CI service, is used as it is. The run removes its server when it ends, and the next run removes a server whose run was killed. `need_core` and its data-core start are gone.
- `10c_dynamic-tests.md` states the test-database rules and their reasons: a throwaway server, never a database a person uses; production's image; one migration per run and one copy per suite; a clean database per test by copy or by rollback; the CI override; cleanup; Flyway on the server's own network, because Docker Desktop does not forward a port Docker picked to the host network. Measured on Studio: its 25 test schemas migrated in 65.5 s on the dev core and in 17.1 s on a tmpfs server.
- `10c_dynamic-tests.md`: a test of `ctl` starts its fixture from an empty environment, or drops every key the gate exports, because a gate setting leaked into Studio's fixtures and turned off the checks they tested.
- `tests/ctl/test-database.test.ts` covers the new path; the data-core tests no longer cover `ctl test`.

## 0.16.1

- `ctl gate`'s tree key copies the index with its timestamps. A plain copy hid a same-size edit made in the second of the last commit, so a run could skip its receipt, or record one for a tree it did not check. A test reproduces the case.
- A gate inside `ctl merge` (`CTL_MERGE=1`) records a `merge-` receipt, and only such a receipt covers a merge run. An ordinary green run on the same tree used to cover it, so the merge skipped the checks' merge-time rules. A merge receipt still covers an ordinary run.
- The release-profile rule is narrowed: a rung builds the release profile only for a test that must run the shipped bytes, keyed by its inputs so a rerun reuses it; every other rung builds the dev profile. 0.16.0 said no rung builds it.
- `10c_dynamic-tests.md` starts the data core only after a test run's settings and tools pass, and starts none when `DATA_SVCS` is empty, as in a ctl test fixture. Studio started it first, so a bad lane setting brought Docker up before it failed.
- `10c_dynamic-tests.md` gives each wait one shared deadline of about a minute, because a gate runs suites beside compiling lanes.

## 0.16.0

- `ctl gate` records each green run in a receipt named by the working tree's git hash, the base tree and the group (`scripts/gate/_receipt.sh`). A run on the same tree and base prints `already green` and runs nothing; `--rerun` runs it again. A run writes its receipt only when the tree did not change while it ran.
- `ctl merge <branch>` lands a branch: in its worktree it merges the default branch in, runs the version step (`scripts/release/versions.sh`, an `[ADAPT]` list of version files) and commits it as `Release: …`, runs `ctl gate --delta <default>` once with `CTL_MERGE=1`, and fast-forwards the main tree. It never pushes. `--minor`, `--major` and `--dry-run`.
- Documentation reaches only the check rung: `AGENTS.md`, `CLAUDE.md` and `README.md` in any folder, `LICENSE`, and other Markdown outside a target's folder.
- The template ships `CLAUDE.md` holding `@AGENTS.md`. `ctl check`'s brief rule needs a plain `CLAUDE.md` with exactly that line beside every `AGENTS.md`, an `AGENTS.md` beside every `CLAUDE.md`, under 200 lines per brief, at most 32 KiB in total, and no `YYYY-MM-DD` date.
- New pages: `15_releases.md` (numbering, `ctl merge`, the version step, packages, the version log) and `16_rust-production.md` (the release profile, `wasm-opt` and a pinned binaryen, parallel image stages, bounded caches, image pruning, measured numbers). `SKILL.md` gains a stage map from prototype to production line, and principle 11.
- The template brief and the pages drop the gate before and after a merge, the rung that can never be removed, and deferrals recorded in the brief; deferrals go in the tracker.
- The template's Rust engine carries the release profile.
- Faster gates, from a measured Studio merge. Each green rung records its own receipt, so a run that went red at a later rung reruns from that rung on the same tree. `ctl test` starts a stopped data core before a suite marked `db` in `_targets.sh`, instead of failing minutes in. `ctl merge` names the release only from the version step's own lines. The pages add the rules behind them: no rung builds the release profile, independent packages build in parallel, finished work lands with `ctl merge` alone, and a test sets its own settings instead of reading the checkout's `.env`.
- The version step works part by part. `VERSION_PARTS` lists each versioned part with where its version lives — `package.json`, `pyproject.toml` (`[project]`), `Cargo.toml` (`[package]` or `[workspace.package]`), a `VERSION` file for any language, or a git tag prefix (`tag:apps/cli/v`) for a Go module — and the paths that ship it. A part moves only when the branch changes its own paths; several manifests can carry one version and must agree; `Cargo.lock`, `uv.lock` and `package-lock.json` move with their manifest; a version the step cannot read, such as a dynamic one, stops it by name. `ctl merge --minor[=PART]` and `--major[=PART]` name the part, and `ctl merge` creates a tag part's tag on the landed commit, only after the gate passes. An empty list still sets nothing.
- `ctl check` gains three rules that the brief stated only as text: a warning, never a failure, for each source file over 500 lines in `ctl`, `apps/` or `scripts/` (generated files, such as `*.gen.*`, do not count, and a `size-cap <path>` exception silences it), and two failures: no code, script or compose file that names a skill page or tracker issue (`doc-pointer <path>` exception), and no edit to a migration already on the default branch. The template's own comments that pointed at skill pages now state their rule instead.
- The template brief states each rule once, points at `ctl --help` instead of copying the verb list, and its security-review placeholder no longer holds a date, which the brief rule would refuse. `wt_default_branch` in `scripts/worktree/_git.sh` is the one place `ctl merge` and `ctl check` learn the default branch.

## 0.15.0

- `ctl setup` and `ctl setup env` merge `.env` with `.env.template` instead of appending missing keys at the end. The result has the template's sections, comments, blank lines and key order, so a new key lands in its section under its comment. Every value `.env` holds is kept byte for byte, and a key `.env` sets where the template shows it commented out takes that line's place. A comment written in `.env` stays with its key. `.env.template.synced`, a copy of the template from the last run, tells a template comment from a local one, so a reworded template comment shows its new text. A key set twice stops the step.
- A key only `.env` has goes to a last section, `# Not in .env.template (kept by ctl setup)`, with its comments. Setup names it and, in a terminal, asks once for the whole list whether to remove the keys; anything but yes keeps them. With no terminal it never asks and never removes. `--remove-unlisted` removes them without asking. Output names keys only, never values.
- The step writes only when the result differs: a temporary file, mode 600, then a rename, after keeping the previous file as `.env.bak`, so a failure leaves `.env` whole. A `.env` that is a link stops the step instead of being replaced.
- `can_ask` and `ask_yes` move from `scripts/dev/_data-core.sh` to `scripts/common/_lib.sh`, because `ctl setup` asks too. `template-core.sha256` changes with it.

## 0.14.0

- `.env.template` gains a RUST section. `CTL_RUST_DEBUG` sets the debug info of the dev and test builds of the repo's own crates. `require_env` and the test settings hand it to Cargo as `CARGO_PROFILE_DEV_DEBUG`, which the test profile inherits, so `ctl dev`, `ctl test` and `ctl gate` all build at that level. A `CARGO_PROFILE_DEV_DEBUG` set in the shell wins, and an empty value leaves `Cargo.toml` to decide. `rust_env_apply` refuses a value Cargo would refuse, naming the key and the values Cargo accepts, and `ctl check` gains the same rule. The key isn't named `CARGO_*`, because `ctl` exports every `.env` key to every process it starts.

## 0.13.1

- Help fits the terminal. `print_help` and `ctl --help` pass through `help_wrap`, which folds each line wider than the window at a space, so a narrow window no longer wraps lines back to column 0. A row's text continues under its own column. A row whose column leaves under 20 columns puts its text on its own lines, and any line indented that deep moves the same way, so a description block stays together. A pipe, or a terminal of unknown width or under 40 columns, gets the text as written. `row` keeps at least two spaces between a term and its text, because that gap marks the column.

## 0.13.0

- Start every bootstrap with `scripts/template.sh copy .`, which copies `template/` whole and never overwrites. `SKILL.md` says how to find the skill folder on each host, lists what each bootstrap answer deletes, compose and gate entries included, and confirms versions before the copy.
- Run `scripts/template.sh verify .` in every mode before an existing `ctl` is extended. A hand-made `ctl` gets an offer to adopt the template (`08_ctl.md` § Adopt an existing repo); an older template copy gets an offer to update its helpers, made only on the user's yes.
- `ctl check` gains a `template core` rule: every helper in `scripts/common/` matches `template-core.sha256` outside its `[ADAPT]` blocks, or `AGENTS.md` records it as an exception. `require_env`'s soft mode is now the `ENV_MISSING` knob.
- `require_tools` names the install step for a missing tool, including a mise shim that cannot run. New convention: a missing tool is installed, never coded around. The `ctl up` plan now requires `jq` instead of falling back to a bare service list.
- Add `ctl worktree create|list|remove|trim`. Every git worktree lives at `.worktrees/<name>`, a link to one of a fixed pool of warm slots that keep their builds, data, logs and `.env` (ports + 100 × the slot number, and its own compose project and image tag). `remove` frees a slot only when its work is clean, idle and merged. The trim deletes Cargo outputs unused for `WORKTREE_TRIM_DAYS`, and skips a slot only while a process `ctl` started or a gate runs there, so a running data core never holds it back. The busy check and `ctl dev db stop` share one process-record check, `process_live_records`, and a gate that waits for its turn keeps its slot busy. `ctl setup` in a slot stops on a new port number instead of adding the main tree's port. `WORKTREE_ONLY=1` makes `ctl dev`, `test`, `gate` and `build` refuse in the main tree. `CTL_ROOT` is the physical path. New page `13_worktree.md`.
- `ctl dev` reuses a running data core and never restarts it, asks before it starts a stopped one, and runs migrations on every launch. Add `ctl dev db [--detach]`, `ctl dev db stop` and `ctl dev stop [--all]`; all stops share `scripts/dev/_stop.sh`. `ctl up` gains `--no-build`, and the `dev` preset selects only the engines. `ctl test e2e` runs as its own compose project, `<name>-e2e`, so it never recreates or removes the dev data core.
- `.env.template` derives `DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` from `BASE_DIR`. Add `ctl setup env`, which writes `.env`, its generated credentials and the storage folders and installs nothing; `ctl setup` runs the same step first. A key whose template comment names its empty default gets no blank warning. `ctl check` gains a storage rule, and a `..` part in a storage path fails.
- `ctl gate` checks what the uncommitted changes reach, and `check` always runs. `--delta <base>` checks the changes since a branch, a commit or a date-time, `--all` checks everything, and `--dry-run` shows the selection. Every skipped rung and target is named.
- The TESTING section of `.env` (`TEST_CPUS`, `TEST_BUILD_JOBS`, `TEST_MEMORY`) sets the cores, compiler jobs and memory budget of every gate and test run, with defaults from the machine. One gate runs per user at a time, under a kernel lock whose path is the same in every shell. New page `10d_test-speed-and-resources.md`.
- The Rust example keeps line tables only for its own crates and no debug info for dependencies. On a measured workspace this cut the disk written per edit from 15.1 GB to 4.3 GB.
- Add development sign-in. With `AUTH_ENABLED=FALSE`, a local request with no credential acts as a reserved `default` user that `V2__users.sql` and `V3__development_identity.sql` create with a fixed id. Backends refuse `FALSE` off loopback and refuse the reserved user under `TRUE`; Compose always sets `TRUE`. Every frontend dev server binds loopback, because its proxy makes each request it accepts look local. New page `14_development-sign-in.md`.
- The ctl tests link a mise-shimmed `jq` to its real binary, so the suite passes when a test replaces `HOME`.

## 0.12.1

- Require direct copying of the CTL template instead of recreating equivalent implementations.
- Add copy commands, safe adaptation guidance for existing repos, and a review of differences against the template before completion.

## 0.12.0

- Add `ctl clean rust [--dry-run]` to remove local Rust debug builds and managed Rust development logs while preserving release builds, lockfiles, data and shared caches.

## 0.11.2

- Use `AGENTS.md` as the project brief without creating a template `CLAUDE.md`.
- Guide existing projects to migrate unique `CLAUDE.md` instructions before removal, and flag a root `CLAUDE.md` in `ctl check`.

## 0.11.1

- Document reusable internal container ports separately from configurable host development ports.
- Add a commented optional beta API address block and matching web-edge Compose wiring example.

## 0.11.0

- Consolidate database engines and migration jobs into the base Compose config; select development services through the dev preset with loopback database exposure.
- Replace development Nginx with native frontend proxies and rewrites; remove the separate db/dev Compose configs and development-proxy settings.
- Add routing and Compose regressions, including live Vite HTTP, WebSocket and HMR checks.

## 0.10.1

- Configure the Flyway migration directory explicitly and copy SQL files to `/migrations` inside the container, avoiding the default-folder deprecation warning.

## 0.10.0

- Add `ctl stop` and a read-only `--dry-run`: stop owned host groups and frozen servers before project containers, retaining containers and data.
- Verify shutdown, allow graceful watcher cleanup, reject unsafe process ownership, and report incomplete host or Docker shutdown.
- Add shared controller locks and a TypeScript/Watchexec Rust development example.
- Standardize PostgreSQL migrations on containerized Flyway with startup ordering and CTL commands.
- Validate development configuration and synchronize dependencies before startup, sharing the setup helpers.
- Add an optional shared-WASM document-engine example under `references/examples/`.
