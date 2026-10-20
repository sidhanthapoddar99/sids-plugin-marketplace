# Changelog

## 0.13.0

- Start every bootstrap with `scripts/template.sh copy .`, which copies `template/` whole and never overwrites. `SKILL.md` says how to find the skill folder on each host, lists what each bootstrap answer deletes, and confirms versions before the copy.
- Run `scripts/template.sh verify .` in every mode before an existing `ctl` is extended. A hand-made `ctl` gets an offer to adopt the template (`08_ctl.md` § Adopt an existing repo); an older template copy gets an offer to update its helpers, made only on the user's yes.
- `ctl check` gains a `template core` rule: every helper in `scripts/common/` matches `template-core.sha256` outside its `[ADAPT]` blocks, or `AGENTS.md` records it as an exception. `require_env`'s soft mode is now the `ENV_MISSING` knob.
- `require_tools` names the install step for a missing tool, including a mise shim that cannot run. New convention: a missing tool is installed, never coded around. The `ctl up` plan now requires `jq` instead of falling back to a bare service list.
- Add `ctl worktree create|list|remove|trim`. Every git worktree lives at `.worktrees/<name>`, a link to one of a fixed pool of warm slots that keep their builds, data, logs and `.env` (ports + 100 × the slot number). `remove` frees a slot only when its work is clean, idle and merged. The trim deletes Cargo outputs unused for `WORKTREE_TRIM_DAYS`. `WORKTREE_ONLY=1` makes `ctl dev`, `test`, `gate` and `build` refuse in the main tree. `CTL_ROOT` is the physical path. New page `13_worktree.md`.
- `ctl dev` reuses a running data core and never restarts it, asks before it starts a stopped one, and runs migrations on every launch. Add `ctl dev db [--detach]`, `ctl dev db stop` and `ctl dev stop [--all]`; all stops share `scripts/dev/_stop.sh`. `ctl up` gains `--no-build`, and the `dev` preset selects only the engines.
- `.env.template` derives `DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` from `BASE_DIR`. Add `ctl setup env`, which writes `.env`, its generated credentials and the storage folders and installs nothing; `ctl setup` runs the same step first. `ctl check` gains a storage rule, and a `..` part in a storage path fails.
- `ctl gate` checks what the uncommitted changes reach, and `check` always runs. `--delta <base>` checks the changes since a branch, a commit or a date-time, `--all` checks everything, and `--dry-run` shows the selection. Every skipped rung and target is named.
- The TESTING section of `.env` (`TEST_CPUS`, `TEST_BUILD_JOBS`, `TEST_MEMORY`) sets the cores, compiler jobs and memory budget of every gate and test run, with defaults from the machine. One gate runs per user at a time, under a kernel lock. New page `10d_test-speed-and-resources.md`.
- The Rust example keeps line tables only for its own crates and no debug info for dependencies. On a measured workspace this cut the disk written per edit from 15.1 GB to 4.3 GB.
- Add development sign-in. With `AUTH_ENABLED=FALSE`, a local request with no credential acts as a reserved `default` user that `V2__users.sql` and `V3__development_identity.sql` create with a fixed id. Backends refuse `FALSE` off loopback and refuse the reserved user under `TRUE`; Compose always sets `TRUE`. New page `14_development-sign-in.md`.
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
