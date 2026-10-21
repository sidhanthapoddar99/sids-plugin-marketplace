# Test speed and resources — what a gate run checks, and what it may use

This page owns the TESTING settings in `.env`, the gate's modes, the one-run lock and the memory lid, the Rust settings that keep a test build small, and the rules that keep a gate run fast without weakening it. The ladder, the rung contract and what counts as green are in `10b_static-checks.md`. Where tests live, and the rules every suite follows, are in `10c_dynamic-tests.md`. How a worktree slot keeps its own warm build folders is in `13_worktree.md`.

A target, on this page, is one app the lint, typecheck and test rungs check: one row of `scripts/gate/_targets.sh`. Every path on this page is relative to the root of a project made from this skill. In the skill, that root is `template/`.

## The TESTING settings

`ctl gate` and `ctl test` read three keys from the TESTING section of the root `.env`. A rung run by name reads them too when it compiles or runs code: `lint`, `typecheck`, `test`, `dead`, `fuzz` and `perf`. One helper, `scripts/common/_test-settings.sh`, reads the keys for every caller, so the gate and the test runner cannot disagree.

| Key | `ctl gate` flag | What it sets | When it is empty |
|---|---|---|---|
| `TEST_CPUS` | `--cpus LIST` | The cores a run may use, as `taskset -c` reads them: `0-7` or `0-3,8-11`. | Every core the shell may use. |
| `TEST_BUILD_JOBS` | `--build-jobs N` | The compiler jobs per Cargo command. Cargo gets the value as `CARGO_BUILD_JOBS`. | One job per core the run may use, at most one per 2 GB of the memory budget, and at least one. |
| `TEST_MEMORY` | `--memory SIZE` | The memory budget of a run: `8G` or `512M`. The gate's memory lid has this size. | 80 % of the memory available when the run starts. |

A value comes from the first source that sets it, in this order: the `ctl gate` flag, the shell, the root `.env`, the default. For compiler jobs, a `CARGO_BUILD_JOBS` already set in the shell comes after `--build-jobs` and before `TEST_BUILD_JOBS`. The helper does not read a `CARGO_BUILD_JOBS` line in `.env`, because `.env` names this budget `TEST_BUILD_JOBS`. Only the ladder forms of `ctl gate` take the flags. A rung run by name reads the shell and `.env`.

On a machine shared with other work, set the keys to leave part of it free. For example, a 32-core desktop that keeps 8 cores for the desktop and an editor:

```sh
# .env, TESTING section
TEST_CPUS=0-23
TEST_BUILD_JOBS=24
TEST_MEMORY=64G
```

The rules the helper follows:

- Every key ships empty in `.env.template`. The helper computes each default, because a number written into the template is a second copy that a filled `.env` keeps after the code changes. The template's comments describe each default in words.
- Each default comes from the machine, never from a number that suits one machine, because the same template runs on a small laptop and on a large workstation. One compiler job on a debug build of a large Rust workspace peaks near 1.3 GB. 2 GB a job leaves room for the linker and for the tests in the same lid. So a laptop with 8 cores and 6 GB free gets 2 jobs, where Cargo's own default of 8 jobs would run it out of memory.
- The gate loads the root `.env` before it reads any setting, because a job count read before the file loads is ignored without a word.
- A bad value stops the run before any rung, and the message names the flag or the key it came from, because a guessed value runs a different build than the one configured. A core the machine lacks, or a core named twice, stops the run too, instead of running on fewer cores than the setting says.
- The helper exports each value once it is resolved. So a run inside the gate, such as the test rung's call to `scripts/test/test.sh`, resolves the same values, a flag's included.
- `TEST_CPUS` binds the whole run with `taskset`: every compiler, test and browser it starts. A Docker container a test starts is bound neither by `TEST_CPUS` nor by the memory lid, because the Docker daemon starts it, not the run.
- Compiler jobs and test workers are separate budgets. libtest and `go test` start one test worker per core the run may use, so `TEST_CPUS` bounds them. `TEST_BUILD_JOBS` bounds only the compilers.

Every run prints one line with its cores and its compiler jobs and says where each came from. The gate also prints its memory lid. `ctl test` has no lid: there the memory budget only sizes the default job count.

## What a gate run checks

| Mode | Command | What it checks |
|---|---|---|
| changed | `ctl gate`, or `ctl gate --changed` | The uncommitted changes: the diff against `HEAD`, plus untracked files. |
| delta | `ctl gate --delta <base>` | The changes from `<base>` to the working tree, plus untracked files. The run counts from the merge base of `<base>` and `HEAD`, and prints the commit it resolved. |
| all | `ctl gate --all`, or `ctl gate all` | Every listed rung on every target. |

`<base>` is any git name of a commit, such as a branch, a tag or a hash, or a local date-time. A date-time is written `2026-10-20`, `2026-10-20 14:30`, `2026-10-20 14:30:05` or `2026-10-20T14:30`. A date-time names the last commit on `HEAD`'s first-parent line at or before that moment. The gate accepts no other date form, because git's own date parser reads text it does not understand as "now", which would select the wrong changes without an error.

Every run prints its plan first: one line per rung that says the rung runs in full, which targets it runs on, or that the changes do not reach it. `--dry-run`, with the changed or the delta mode, prints every changed path, its owner and the plan, and runs nothing. `--dry-run` does not go with `--all`, which has nothing to select. `static` and `dynamic` work in every mode.

How the selection works, in `scripts/gate/_changed.sh`:

- Each changed path gets one owner, from the owner rules in the table below. A deleted path counts, and a renamed path counts at both ends.
- lint, typecheck and test run only on the targets their changed paths reach. A target the rung does not list, such as `database` for typecheck, is not that rung's work.
- `check` always runs in full, because it proves the repo contract, which no owner rule covers.
- `dead`, `audit`, `build` and `e2e`, when listed, run in full whenever anything changed, because each reads the whole repo.
- The plan names each rung the changes do not reach. The closing line of a partial run names every rung and target it skipped, so a partial run never reads as a full one.

| Changed path | Owner | Why |
|---|---|---|
| `ctl`, `scripts/` | everything | They drive every rung. |
| `.mise.toml` | everything | It sets the toolchains. |
| `apps/packages/` | everything | A shared package reaches every app that imports it. |
| a path inside a target's folder | that target, plus the targets `GATE_REACHES` adds | The template ships `database` reaching `api` and `engine`, because the backends' integration tests run against the migrated schema. |
| `docker/`, `AGENTS.md`, `README.md`, `CHANGELOG.md`, `LICENSE` | `check` | Only the check rung reads them. |
| any other path, such as `.env.template` or `.gitignore` | everything | No rule names it. |

The selection fails toward running more. A path no rule names widens the run to every rung on every target, because a skipped check that looks green is a wrong answer that looks right. A missing rule costs time; a wrong rule lets a bug through. Add a narrower rule only for a dependency you know. Record it as a row of `AGENTS.md` § Recorded choices, because the next audit compares the repo against the brief. The same holds when the change set cannot be read: a repository with no commit yet counts every file, and a plain `ctl gate` outside git widens to everything. `--delta` outside git stops by name, because it has no history to count from.

When you add, rename or delete an app, edit its row in `_targets.sh`: its name, its folder, its ecosystem and the rungs that check it. lint, typecheck, `ctl test` and the selection all read that one table. `GATE_REACHES` may name only rows of the table, and every gate run stops when it names another, so a rename cannot drop a target without a word.

How to use the modes:

- While you work, run the focused check first: `ctl gate lint <app>`, `ctl gate typecheck <app>` or `ctl test <app>`, because a focused check takes seconds and does not wait for the lock. Each takes several apps.
- Before you hand the work over, run the gate once over the whole change. Run a plain `ctl gate` when all of the work is uncommitted. Run `ctl gate --delta <the commit you started from>` once any of it is committed, because a plain run sees only the uncommitted rest.
- To check a branch before it merges, run `ctl gate --delta <the branch it merges into>` on the branch. To check a merge right after `git merge`, run `ctl gate --delta ORIG_HEAD`. `ORIG_HEAD` is the commit the target branch held before the merge, so the run covers everything the merge brought in.
- With `WORKTREE_ONLY=1`, the main tree runs no gate (`13_worktree.md` § The main-tree guard). Merge the target into the branch in its worktree, run `ctl gate --delta <target>` there, then fast-forward the main tree with `git merge --ff-only <branch>`. The gated tree is then exactly the tree the main tree gets.
- Run `--all` only when the selection itself is in doubt, such as when you suspect an owner rule is wrong, because the selection already widens on every path it cannot place.
- Read the closing line. It says whether the run was full, widened and why, partial and what it skipped, or had nothing to run.

## One run at a time, under a memory lid

The gate holds a kernel `flock` on `/run/user/<uid>/ctl-gate-<uid>.lock` for the whole run, or on `/tmp/ctl-gate-<uid>.lock` when the user has no `/run/user` folder. Every checkout and every project made from this template shares that one lock per user, because two heavy runs at once can run a machine out of memory and end the login session. The path ignores `XDG_RUNTIME_DIR`, because a shell without it would pick another file and let a second run start beside the first. `GATE_LOCK_FILE` overrides it. A second run prints which command holds the lock, in which checkout, and on which rung, then waits until it ends. The kernel drops the lock when the last process of the run ends, a killed run included, so there is never a stale lock file to remove. A process the run leaves running in the background keeps the lock until it ends. Every run, a waiting one included, also holds a shared `flock` on `ctl-gate.lock` in its checkout's git folder, where `git status` never sees it. `ctl worktree` tests that lock without waiting (`scripts/worktree/_busy.sh`), so a gate that waits for its turn keeps its slot busy too. For a branch whose scripts predate that file, it tests the user's lock and reads the `checkout=` line to learn which checkout holds it. Only the ladder takes the lock: a rung run by name and `ctl test` do not, so a focused check stays possible during a long gate.

The whole run, every worker, compiler and browser, runs inside one memory-capped scope the size of the memory budget, with swap off. A run that reaches the lid is killed with exit 137, and the machine stays up. The message names the settings to change: a bigger `--memory` or `TEST_MEMORY`, or fewer `--build-jobs` or `TEST_BUILD_JOBS`. The lid needs `systemd-run --user`. Without it, as on WSL with no systemd or inside a container, the run goes without a lid and says so on one line.

## Rust builds that write less

The Rust example's `Cargo.toml` keeps line numbers for the workspace's own crates and drops debug info for dependencies, in development and test builds. Copy these two profile sections into the root `Cargo.toml` of every Rust workspace:

```toml
# The test profile inherits dev. A panic or a backtrace still names the file and line.
[profile.dev]
debug = "line-tables-only"

# "*" is every package that is not a member of this workspace: the dependencies.
[profile.dev.package."*"]
debug = false
```

Cargo rewrites each test binary whole after an edit, and full debug info is most of each binary. On a measured Rust workspace, one edit writes 15.1 GB to disk with full debug info and 4.3 GB with this profile. A cold test build writes 25.1 GB and takes 138 s with full debug info, and writes 7.6 GB and takes 103 s with this profile. A panic message keeps its file and line, because those come from the panic's own location data, not from debug info.

The RUST section of `.env` changes the level without an edit to `Cargo.toml`. `CTL_RUST_DEBUG` takes the values Cargo's `debug` setting takes: `0`, `line-tables-only`, `limited` or `full`. Set `CTL_RUST_DEBUG=full` for a debugger session, so the debugger shows variables in the workspace's crates. `ctl dev`, `ctl test` and `ctl gate` hand it to every Cargo command they start as `CARGO_PROFILE_DEV_DEBUG`, which the test profile inherits (`rust_env_apply` in `template/scripts/common/_lib.sh`). A `CARGO_PROFILE_DEV_DEBUG` set in the shell wins, and an empty value leaves `Cargo.toml` to decide. Dependencies keep `debug = false`, because a package section in `Cargo.toml` outranks the profile-wide setting.

- Keep the RUST section empty unless the repo needs another level all the time. A cargo or rust-analyzer you run yourself reads only `Cargo.toml`, so a value in `.env` makes its builds differ from the ones `ctl` starts. A different level writes another copy of every compiled crate into `target/`.
- The key is named `CTL_RUST_DEBUG`, not `CARGO_PROFILE_DEV_DEBUG`, because `ctl` exports every `.env` key to every process it starts. With its own name, `ctl` checks the value first, and `ctl check` names a value Cargo would refuse. A repo with a tool that refuses Cargo variables in its environment can also hand the value to only the builds that should get it, such as one that hashes its build inputs.

- Leave `CARGO_INCREMENTAL` on, as Cargo's default has it. On the same workspace, a test build after a one-line edit takes 15.7 s with it and 56 s without.
- Never export one `CARGO_TARGET_DIR` for every checkout. Each checkout keeps its own `target/`, because one shared folder makes checkouts wait on Cargo's build lock and rebuild each other's workspace crates.
- Use no compiler cache such as sccache. On the measured workspace it saves about 7 % of a gate: the workspace's own crates set the pace, and their cache keys include the checkout's path, so another checkout never hits them. Every miss also writes each compiled piece twice. A warm worktree slot, a checkout that keeps its own `target/` between tasks, gives the same reuse without the second copy.
- In Cargo, the opt-in switch for a heavy test that `10c_dynamic-tests.md` asks for is a feature. The default `cargo test` then skips the test's compile and its link. On the measured workspace the test binaries take 765 MB without the switch and 324 MB with it, with every default test kept. In the member crate's `Cargo.toml`:

```toml
[features]
# Off by default. `cargo test --features heavy-tests --test full_corpus` turns it on.
heavy-tests = []

[[test]]
name = "full_corpus"                  # tests/full_corpus.rs
required-features = ["heavy-tests"]   # without the feature, cargo neither builds nor runs it
```

## Rules for fast verification

These hold for any project, and for every runner a project adds. The order of the rungs themselves is the ladder in `10b_static-checks.md`.

- Inside one rung or runner, run the checks that compile nothing before any check that compiles, because a formatting slip found after a ten-minute build wastes the build. The lint rung runs ruff, cargo fmt, oxlint and gofmt on every target before clippy and golangci-lint.
- Check prerequisites, such as a tool, a running engine or a free port, before a build starts, for the same reason.
- Bound the fan-out by the budget. A lane is one of several commands a runner starts at once. A runner that starts lanes takes their count from a key in the TESTING section of `.env`, with a default derived from the machine. The runner divides `CARGO_BUILD_JOBS` between its lanes, because four lanes that each take eight jobs start thirty-two compilers.
- Reuse a verified artifact only when its inputs match exactly: the source, the toolchain, the profile, the features and every environment value that enters the build. A mismatch is a miss that rebuilds, never a pass, because an artifact built from other inputs proves nothing about this change. Leave out of the inputs what does not change the output, such as the compiler job count, so it causes no needless miss.
- Keep a green run's output small: its counts, not its passing lines. A reader who pages through passing lines spends attention, and an agent spends context, on nothing. `ctl gate -q` prints one line per green rung.
- Keep each failure whole. A red run prints its failure in full, because a failure cut short cannot be diagnosed. `ctl gate -q` prints a red rung's whole output.
- Let the exit status decide the result, never the text, because a tool's wording changes between versions.
- Measure one variable at a time. Say which build was cold and which was warm, because a cold build, a warm build and a build after one edit answer different questions, and a time with no cache state cannot be compared.
- Run each check once for each set of inputs. When a later step, such as a review checklist, asks for a check that already passed on the same files, do not run it again, because its result cannot change.
- Wait for `ctl gate` to exit. Then read its closing line, instead of polling its output, because each poll spends context on partial output and only the closing line is the verdict.
- Follow the suite rules in `10c_dynamic-tests.md` § Rules: one setup per suite, disposable resources the run owns, waits on an exact state, and heavy tests behind an opt-in switch.

## Template

- `scripts/common/_test-settings.sh`: the TESTING settings, their checks and their defaults.
- `scripts/gate/all.sh`: the modes, the plan and the closing line.
- `scripts/gate/_changed.sh`: the change set, the owner rules and `GATE_REACHES`.
- `scripts/gate/_targets.sh`: the targets of lint, typecheck and test.
- `scripts/gate/_lock.sh`: the lock and the memory lid.
- `apps/example-engine-rust/Cargo.toml`: the development profile.
- `.env.template`: the TESTING section.
