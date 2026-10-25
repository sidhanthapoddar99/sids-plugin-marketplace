# Changelog

## 0.16.0

- `ctl gate` records each green run in a receipt named by the working tree's git hash, the base tree and the group (`scripts/gate/_receipt.sh`). A run on the same tree and base prints `already green` and runs nothing; `--rerun` runs it again. A run writes its receipt only when the tree did not change while it ran.
- `ctl merge <branch>` lands a branch: in its worktree it merges the default branch in, runs the version step (`scripts/release/versions.sh`, an `[ADAPT]` list of version files) and commits it as `Release: …`, runs `ctl gate --delta <default>` once with `CTL_MERGE=1`, and fast-forwards the main tree. It never pushes. `--minor`, `--major` and `--dry-run`.
- Documentation reaches only the check rung: `AGENTS.md`, `CLAUDE.md` and `README.md` in any folder, `LICENSE`, and other Markdown outside a target's folder.
- The template ships `CLAUDE.md` holding `@AGENTS.md`. `ctl check`'s brief rule needs a plain `CLAUDE.md` with exactly that line beside every `AGENTS.md`, an `AGENTS.md` beside every `CLAUDE.md`, under 200 lines per brief, at most 32 KiB in total, and no `YYYY-MM-DD` date.
- New pages: `15_releases.md` (numbering, `ctl merge`, the version step, packages, the version log) and `16_rust-production.md` (the release profile, `wasm-opt` and a pinned binaryen, parallel image stages, bounded caches, image pruning, measured numbers). `SKILL.md` gains a stage map from prototype to production line, and principle 11.
- The template brief and the pages drop the gate before and after a merge, the rung that can never be removed, and deferrals recorded in the brief; deferrals go in the tracker.
- The template's Rust engine carries the release profile.
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
