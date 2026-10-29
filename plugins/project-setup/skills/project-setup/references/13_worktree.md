# Worktrees — `.worktrees/`, warm slots and `ctl worktree`

Every git worktree of a repo lives at `<repo>/.worktrees/slot-<n>`, one slot of a fixed pool, and `ctl worktree create <branch>` puts a branch in one. A new branch therefore builds warm, the repo stops growing with every worktree, and the disk takes far fewer writes. This page owns the design and its reasons. The rule an agent follows is one bullet in `template/AGENTS.md` § Working rules.

Template: `template/scripts/worktree/` (`worktree.sh` and its helpers), the guard line and the physical `CTL_ROOT` in `template/ctl`, `CTL_ROOT` in `template/scripts/common/_lib.sh`, the WORKTREES section of `template/.env.template`, and `/.worktrees/` in `template/.gitignore`.

## Terms

| Term | Meaning |
|---|---|
| Main tree | The repo's main checkout, whatever branch it has checked out. It owns `.worktrees/`. Every slot's `.env` is written from its `.env`, and merging happens there. |
| Slot | A git worktree at `.worktrees/slot-<n>`. Its path never changes, and nothing deletes it. |
| Free, taken | A free slot has a detached HEAD. A taken slot is on a branch. |
| Name | A branch name. Git's own worktree list is the one record of which slot holds which branch. |
| Busy | Something `ctl` started in the slot still runs: a recorded process, a container of the slot's stack, or a gate run. |

## The layout

```
<repo>/                            # the main tree
├── .gitignore                     # holds /.worktrees/, so git never sees a slot
└── .worktrees/
    ├── slot-1/                    # a git worktree, taken: on branch feat/login
    │   ├── .env                   # written on its first use: ports + 100, COMPOSE_PROJECT_NAME ends in -slot-1, TAG=dev-slot-1
    │   ├── apps/<engine>/target/  # its build folders stay across branches: target/, node_modules/, .venv/
    │   ├── data/                  # its own engine data, from the relative BASE_DIR or DATA_DIR
    │   └── logs/                  # its own process records, logs and backups
    ├── slot-2/                    # free: a detached HEAD, its builds kept warm for the next branch
    ├── .slots.lock                # one ctl worktree command at a time
    └── .trim-stamp                # the time of the last trim
```

A typical round, from the main tree:

```sh
cd "$(ctl worktree create feat/login)"   # create prints only the slot's path, .worktrees/slot-1
ctl setup                                # only on a new slot's first use: installs its dependencies
ctl dev                                  # work, test and commit here, as in any checkout
ctl stop                                 # stop the slot's dev apps and its containers
ctl merge feat/login                     # merge main in, set versions, one gate here, fast-forward main
ctl worktree remove feat/login           # frees slot-1; the branch and the builds stay
```

`ctl merge` runs its gate in the slot, because a gate writes build outputs, and with `WORKTREE_ONLY=1` the main tree runs none. It then fast-forwards the main tree, so the main tree gets exactly the gated tree (`15_releases.md`). `remove` refuses while the slot's containers run, so `ctl stop` comes first: the data core outlives `ctl dev` on purpose.

## The commands

| Command | Does | Refuses, and changes nothing, when |
|---|---|---|
| `ctl worktree create <name> [--from <ref>]` | Takes the lowest free slot, or adds one up to `WORKTREE_SLOTS`. Puts it on branch `<name>`: the existing branch, or a new one from `<ref>`, by default the main tree's HEAD. Prints the slot's path, the one to work in. On a slot's first use, writes its `.env` (§ A slot's `.env`). | The name is no valid branch name. `--from` names an existing branch. The branch is checked out elsewhere. The lowest free slot has changes or is busy. Every slot is taken. The slot's `.env` cannot be made safe. Git does not ignore `.worktrees/`. |
| `ctl worktree list` | Shows each slot: its branch or `free`, clean or dirty, merged into the main tree or not, the size of its builds, and its last checkout or commit. Warns about a worktree outside `.worktrees/`, and names any link an older `ctl` made (§ The pool's one record). | Never refuses. It exits 1 when the pool breaks the state rule below. |
| `ctl worktree remove <name>` | Detaches the HEAD of the slot that holds branch `<name>`, so the slot is free. Keeps the branch, the slot and its builds. | The worktree has uncommitted changes or untracked files git does not ignore. The branch's work is not in the main tree's HEAD. The slot is busy. |
| `ctl worktree trim [--days N] [--dry-run]` | In every slot, deletes Cargo outputs that no build used for N days (§ The trim). `--dry-run` only counts. | Never refuses a slot. It skips a slot where a process `ctl` started or a gate still runs, and a profile Cargo is building in, and names each. |

`remove` has no force option, because a freed slot goes to the next `create`, so its work must already be in the main tree. `remove` keeps the branch, because deleting a branch stays a person's call.

A branch counts as merged when it is an ancestor of the main tree's HEAD, or when merging it into that HEAD would change nothing. The second test catches a branch merged by rebase or squash, whose old commits stay outside HEAD's history although their work is in. Both answers are certain, so neither frees a slot whose work is missing. The test needs `git merge-tree --write-tree`, from git 2.38. An older git makes `remove` stop with that reason.

The settings are read from the shell, else from the main tree's `.env`, whichever checkout runs `ctl`. An empty value keeps the default.

| Key | Default | Meaning |
|---|---|---|
| `WORKTREE_SLOTS` | 4 | The most slots. Each slot holds one full set of builds, so this caps the disk the pool can take. |
| `WORKTREE_TRIM_DAYS` | 7 | The trim deletes outputs no build used for this many days. |
| `WORKTREE_ONLY` | on | `0` turns off the main-tree guard, for a checkout with no slots such as CI (§ The main-tree guard). |

## Why a pool of slots

Every new worktree path costs a full build, and an old path never gives its build back:
- Cargo keys a workspace's own crates by their absolute path, so a fresh worktree path builds them from cold, even on the same commit.
- `node_modules/` and `.venv/` hold absolute paths too, so each path installs its own copy.
- Cargo never deletes an old output. On a measured Rust workspace, one long-lived integration worktree held 203 GB of build folders: 101 GB of old incremental data and 102 GB of old outputs.

A slot's path never changes, so a branch that moves into a slot reuses everything the last branch built. The fixed pool caps how many sets of builds exist, and the trim caps how long an unused output stays.

## The pool's one record

Git's worktree list already says which branch each slot holds, so it is the pool's only record. You work in `.worktrees/slot-<n>`, the path `create` prints, and `ctl worktree list` shows which branch is where. A second record, such as a link named after each branch, would only repeat that fact, and two records of one fact can disagree.

The pool's state rule: every `slot-<n>` folder is a worktree git lists. Every command reads the whole pool first. When it finds anything else, it names each problem and changes nothing, because a guess could put work on the wrong branch. So never move, delete or `git worktree remove` a slot. Switch a slot's branch through `ctl worktree`, so the slot stays free or taken as the pool expects.

An older `ctl` named each slot with a link, `.worktrees/<branch> -> slot-<n>`. A `create`, `remove` or `trim` that succeeds deletes such a link, and the folders it leaves empty, and says so; one that refuses changes nothing. `list` names it. A link that points anywhere else is left alone.

## The physical path

`ctl` and `scripts/common/_lib.sh` set `CTL_ROOT` with `pwd -P`, the physical path. A person may still reach a checkout through a symlink of their own. Every path that `ctl` writes down must stay one path:
- Cargo's outputs and the paths baked into them;
- the `project` file of each process record under `LOGS_DIR/run/`, which `ctl stop` compares with `CTL_ROOT`;
- the compose working-directory label, which `ctl stop` matches;
- the `checkout=` line of the gate lock, which the busy check compares.

## One build folder per slot

Each slot keeps its own build folders. Three ways to share builds between slots were rejected:
- One `CARGO_TARGET_DIR`, or one build folder linked into every slot. The slots would wait on Cargo's build lock, and each would still rebuild the workspace's own crates, which Cargo keys by their source path.
- A compiler cache such as sccache. It cannot share the workspace's own crates between checkouts either, and every miss writes each compiled piece twice. A warm slot gives the reuse with one copy.
- Copy-on-write clones of a build folder. They would avoid both problems, but they need a filesystem such as btrfs or XFS, and many development disks use ext4.

`10d_test-speed-and-resources.md` § Rust builds that write less holds the two resulting rules, no shared `CARGO_TARGET_DIR` and no compiler cache, with their measurements.

## A slot's `.env`

A slot's first use writes its `.env` from the main tree's `.env`, mode 600, with three changes:
- Every `*_PORT` key that holds a number gets + 100 × the slot number. A step of 100 keeps each port's last two digits, so a port stays recognisable in every slot. A step of 1 collides at once with a neighbouring service's port.
- `COMPOSE_PROJECT_NAME` gets `-slot-<n>`, so each slot runs its own stack. An empty name starts from the main tree's folder name, as compose would read it.
- `TAG` becomes `dev-slot-<n>`, whatever the main tree's `TAG` is, so each slot builds and runs its own images. With one shared tag, two slots that start `ctl dev` together race on one migration image, and one slot's migrations can run against the other slot's database. A slot is for development, so it never takes a main tree's `auto`, `none` or pinned production name.

`BASE_DIR` and the storage paths are copied as they are. Relative paths resolve inside the slot, so each slot keeps its own `data/` and `logs/`. The storage contract itself is in `02_env.md`. Later uses of a slot keep its `.env`, and `ctl worktree` never rewrites one, so a hand edit stays.

`create` refuses, naming the key, when a value would let the slot reach the main tree's services or files:
- a port written as a number inside another value, such as a URL: write `${API_PORT}`, so the offset reaches it;
- a `*_PORT` that is neither a number nor a `${NAME}` reference, or one that would pass 65535;
- `BASE_DIR`, `DATA_DIR`, `LOGS_DIR` or `BACKUP_DIR` that is absolute, has a `..` part, or is built from another key than these four, because two checkouts would then share one database;
- a `*_PORT` that `.env.template` declares and the main tree's `.env` lacks, because the slot would lack it too;
- a port that the main tree's `.env`, another slot's `.env` or `PORT_PRESETS` already uses.

An absolute storage path is legal in the main tree, for example on a deployment host. That host runs no slots.

`ctl setup` in a slot never adds a port number, because it cannot know the slot's offset, and the main tree's port would let the slot's apps reach the main tree's. When a branch adds a `*_PORT` key with a number to `.env.template`, `ctl setup` in the slot stops, names the key and changes nothing. Add the key by hand at the slot's offset, which the first line of the slot's `.env` names, then run `ctl setup` again. For the same reason, `ctl setup` in a slot without a `.env` stops instead of copying `.env.template`.

## Busy slots

`create` and `remove` refuse a busy slot, because switching a branch under a running stack, dev loop or gate breaks it. One shared function, `slot_busy` in `_busy.sh`, judges three things by `ctl`'s own records:
- **Processes.** A process recorded under the slot's `LOGS_DIR/run/` that may still run: the records `ctl dev` and `ctl build start` write and `ctl stop` reads. A record `ctl` cannot verify counts too: a link, a record that names another checkout, or a live PID with no start time. `ctl dev db stop` refuses on the same check, `process_live_records` in `scripts/common/_process.sh`. The busy check reads the slot's own `.env` with the caller's storage keys unset, because a caller that `ctl` started elsewhere exports its own absolute paths.
- **The gate.** A gate that waits or runs in the slot. Every gate run holds `ctl-gate.lock` in its checkout's git folder from before its wait to its end, and the busy check tests it with an exclusive `flock` that never waits. A waiting gate counts, because a branch switch before it starts would make it check the wrong branch. For a branch whose scripts predate that file, the check falls back to the gate lock that the slot's `scripts/gate/_lock.sh` names, tested with a shared `flock` that never waits and never writes. A held lock counts when it lies inside the slot, when its `checkout=` line names the slot, or when it has no `checkout=` line, because then `ctl` cannot tell whose it is.
- **Containers.** Running containers of the slot's compose project. When Docker is missing or stopped, no container can run. Any other Docker failure counts as busy, because `ctl` cannot tell.

The trim skips a slot only for its processes and its gate, because those read and write build outputs. A container runs from an image and reads no build output, and the data core outlives `ctl dev` on purpose, so a running data core never holds a slot's trim back.

## The trim

Cargo never deletes an old output, so a slot that lives for good keeps every build of every branch it carried. Deleting whole build folders would make the next build rewrite all of them, so the trim deletes by age, entry by entry:
- **Where.** Only the entries of `deps/`, `build/`, `.fingerprint/` and `incremental/` inside a Cargo profile folder, `<target>/<profile>` or `<target>/<triple>/<profile>`, beside the `CACHEDIR.TAG` that Cargo writes. Never sources, `.env`, `data/`, `logs/`, `node_modules/` or `.venv/`, and never a profile's own files, such as an uplifted binary.
- **What counts as used.** An entry goes when the newest read and the newest write of everything in it are older than `WORKTREE_TRIM_DAYS`. A folder counts only its writes, because walking it, as `du` or `ctl worktree list` does, sets its read time. On a disk mounted with `noatime`, reads are never recorded, so only writes count. That costs extra rebuilds, never a wrong result.
- **When.** By hand, or on its own: `create` and `remove` run it when the last trim is more than 7 days old, so nobody has to remember it and no system timer is installed. A failed weekly trim never undoes the command that ran it.
- **Safety.** A slot where a process `ctl` started or a gate still runs is skipped whole, and its containers do not count (§ Busy slots). A profile whose `.cargo-lock` a running Cargo holds is skipped too, because a build outside `ctl`, such as an editor's `cargo check`, may be writing there. The trim holds that lock while it deletes, so no Cargo build starts there halfway.
- **Cost.** Cargo rebuilds a unit whose output or fingerprint is missing, so a trimmed entry costs one rebuild and nothing else.

The trim covers the slots only. In the main tree, `ctl clean rust` removes the debug builds.

## The main-tree guard

`ctl dev`, `ctl test`, `ctl gate` and `ctl build` refuse in the main tree and point at `ctl worktree create`. The guard is on by default, because a build in the main tree costs twice:
- **Time.** The main tree's build folders fall behind while the work happens in slots, so a build there recompiles most of the dependency graph. On Studio, one gate in the main tree took 836 s, where the same kind of gate in a warm slot took 340 s; Cargo recompiled 345 crates in the typecheck rung alone, third-party crates among them.
- **Disk.** Each build folder in the main tree is a second full set of outputs beside the slots', often several GB per Rust app.

The guard lets these through:
- help, anywhere on the line;
- `ctl build start`, which only serves a frozen build, and `ctl build clean`, which frees space;
- `ctl dev db`, which runs the data core in Docker as `ctl up` does, and `ctl dev stop`, which only stops processes, because stopping must always work;
- `ctl setup`, always, because a new checkout must be able to set itself up, and because `create` refuses a main `.env` that lacks a template port until setup has run there;
- every other verb, such as `ctl up`, `ctl db` and `ctl worktree`, because the guard covers only the verbs that build the apps into the checkout.

`.env.template` ships `WORKTREE_ONLY=1`, and an empty value or a `.env` without the key means on too, so the default holds in an older `.env`. `0` turns the guard off. It accepts empty, `0` or `1`, and refuses any other value. A value set in the shell wins over `.env`, so one command runs unguarded with `WORKTREE_ONLY=0 ./ctl <verb>`. Outside a git checkout there is no worktree to work in, so nothing is guarded.

Two checkouts set it to `0`, because they have no slot to work in:
- **CI.** A CI clone is a main tree with no `.worktrees/`, so its job runs `WORKTREE_ONLY=0 ./ctl gate --delta <base>` (`10b_static-checks.md`).
- **A bootstrap's first gate.** The copied template is not committed yet, so no slot can check it out; the bootstrap runs that one gate with `WORKTREE_ONLY=0` (`SKILL.md`, Bootstrapping, step 8).

## Disk writes and wear

A solid-state drive is rated for a fixed amount of data written. On a machine that builds Rust all day, build folders are most of what it writes: on the measured machine, daily writes reached several hundred GB, and a drive rated for 100 TB written wears out within months at that rate. Two parts of the template keep writes down, and they work together:
- **Warm slots** turn each new branch into an incremental build, where a fresh worktree path pays a cold build. On the measured Rust workspace, a cold test build wrote 25.1 GB with full debug info.
- **The Rust debug profile** shrinks what each incremental build writes, because Cargo rewrites each test binary whole after an edit, and debug info made most of each binary. On the same workspace, one test edit wrote 15.1 GB with full debug info and 4.3 GB with the profile. The settings are in `10d_test-speed-and-resources.md` § Rust builds that write less.

The trim then bounds what an idle slot keeps. To check a drive, read field 7 of `/sys/block/<device>/stat`, the 512-byte sectors written since boot, which needs no root. `smartctl -A` reports the drive's lifetime writes and wear.

## Turning an existing worktree into a slot

Slots made by `ctl worktree create` never move. A worktree made by hand and moved into `.worktrees/slot-<n>` keeps its old absolute path inside some build outputs:
- Cargo does not rebuild when only the absolute path changes, so a test that bakes in `env!("CARGO_MANIFEST_DIR")` still reads the old path.
- A moved Python `.venv` keeps scripts that point at the old interpreter.
- bun links each file of a `file:` package by its absolute path, so those links break once the old folder is gone.

To convert one:
1. Run `git worktree move <old path> .worktrees/slot-<n>`, with a number no slot has.
2. Keep it on its branch, so it stays taken, or run `git switch --detach` in it to free it.
3. Move its `.env` aside, because it still has the main tree's ports. The next `create` that takes the free slot writes a fresh one; a taken slot needs its ports edited by hand.
4. Delete its `target/`, `node_modules/` and `.venv/` folders, then run `ctl setup` in it.

A gate can pass on stale paths and break later on the first rung that reaches them, so rebuild everything that holds the old path, not only what the last run tripped on.

## Known limits

- A slot keeps its ignored files across branches, `data/` included, so a new branch inherits the last branch's development database. When a branch needs an empty one, stop the slot's stack with `ctl stop` in the slot, then reset the slot's own `data/` the way the project resets its development database.
- A port or storage path exported in the shell wins over a slot's `.env`, as everywhere in `ctl`. Run `ctl` in a slot from a plain shell, not from a process that another checkout's `ctl` started.
- The busy check sees what `ctl` started. A process started by hand in a slot is not seen, except a Cargo build, which the trim's lock check catches.
- The scripts need Linux or WSL, git, `flock`, `/proc`, and GNU `find`, `du`, `numfmt` and `timeout`. `ctl worktree` names a missing tool.
