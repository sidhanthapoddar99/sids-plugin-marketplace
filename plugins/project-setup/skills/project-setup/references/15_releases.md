# Releases — versions, landing work, and what each release records

A version tells people what an update risks. This page owns how a repo numbers its releases, when the number moves, and the one command that lands work: `ctl merge`. The gate it runs is `10d_test-speed-and-resources.md`'s; the image it ships is `09_production.md`'s.

## The rule in one line

Versions move once, when a branch lands on the default branch, and `ctl merge` moves them. No commit on a branch raises a version by hand, because a version names what people receive, and people receive a merge, not a commit.

## Numbering

A version is `<major>.<minor>.<patch>`, written bare in its manifest and shown to people as `v<major>.<minor>.<patch>`, because npm, Cargo and Python tooling refuse a leading `v`.

| Part | Goes up when an update | Example |
|---|---|---|
| major | breaks existing data, links or workflows | a saved file needs a conversion to open |
| minor | adds something and keeps everything working | a new tool |
| patch | fixes something and keeps everything working | a bug fix, a faster build of the same behavior |

Every part to the right of the raised one becomes 0, as `1.4.2` becomes `1.5.0`, because readers compare versions part by part.

What counts as a change is mechanical: a branch that touches shipped code gets a patch release. Shipped code is source under `apps/`, apart from tests, fixtures and Markdown. A branch that changes only tests, docs or tooling ships no version, because people receive nothing new. The minor and major parts are the person's call, given as `ctl merge <branch> --minor` or `--major`, because only a person knows whether an update adds or breaks.

## `ctl merge <branch>`

The one way work reaches the default branch. In the worktree that holds `<branch>` it:

1. merges the default branch into `<branch>` when the branch does not already contain it. A conflict stops the run with nothing half merged;
2. runs the version step, `scripts/release/versions.sh`, and commits what it sets as `Release: <versions>`;
3. runs one gate, `ctl gate --delta <default branch>`, on the merged tree, with `CTL_MERGE=1` in its environment;
4. fast-forwards the main tree's default branch to `<branch>`.

It never pushes, never rewrites a commit and fast-forwards only. `--dry-run` prints the plan and the versions it would set.

Why one command instead of steps in `AGENTS.md`:

- Two branches that each passed the gate can still break each other, so the gate must run on the merged tree. Running it there once, and fast-forwarding, means the default branch holds exactly the tree that passed. A gate before the merge and another after it is the same check twice.
- The gate records each tree it passed (`10d` § One run per tree), so `ctl merge` on a branch whose merged tree already passed costs no second run.
- A rule an agent must remember drifts; a rule `ctl` runs does not. A version bump in every commit, a forgotten bump, and a gate run three times per merge are each a habit that comes back after it is fixed by hand.

`CTL_MERGE=1` lets a project make a check strict only at merge time. Studio's engine ledger is the example: on a branch a changed engine is reported, and under `ctl merge` it must be recorded.

## The version step

`template/scripts/release/versions.sh` sets the product's one version. Its `[ADAPT]` list `VERSION_FILES` names the manifests that carry it, such as `apps/web/package.json` or a Rust workspace's `Cargo.toml` (`[workspace.package] version`). An empty list means the product has no version yet, and the step sets none. For a `Cargo.toml` it also runs `cargo update --workspace --offline` beside it, because `Cargo.lock` records each member's version and a `--locked` build refuses a lock that disagrees.

A project with parts that carry their own version extends this step and records the extension in `AGENTS.md` § Exceptions. The shape Studio uses for its document engines:

| Part | Trigger | What the step writes |
|---|---|---|
| each engine | its input hash differs from its ledger entry | the next patch version in `Cargo.toml` and the lock, a `Compatible` migration step, the ledger entry, the release's baseline fixtures |
| the product | shipped code changed, or any engine moved | the next patch version, or the part `--minor`/`--major` names |
| an engine's major version | raised by hand, with its own conversion step | kept, and recorded |

The extension keeps the rule: each trigger is a fact the code can read, so no agent decides when a version moves.

## Packages

- Keep one version per workspace. A Rust workspace sets `version` once in `[workspace.package]`, and members say `version.workspace = true`. A crate that never leaves the repo sets `publish = false`.
- Pin shared dependencies once in `[workspace.dependencies]`, and in a JS group every manifest names the same version (`04_stack.md`).
- Commit every lockfile: `Cargo.lock`, `bun.lock`, `uv.lock`. A release builds from the lock, so two builds of one commit get the same dependencies.
- A published crate runs `cargo semver-checks` before its version is set, because it reads the public API and says whether the change is major. Choose `--major` when it says so.
- A source-only package (`11_conventions.md`) carries no version of its own; the product's version covers it.

## What each release records

- A changelog or version log entry per new version: what changed for people, and, for a speed or size change, the measured number with the commit that measured it. Write it in the docs repo or `CHANGELOG.md`, as the brief records. `ctl merge` prints the reminder after a version moves.
- A tooling change that ships no version, such as gate speed or build disk use, gets its own entry in the same log, so the effort is visible.
- A released version never changes meaning: its ledger entries, fixtures and tags stay as they were released.

## Industry names

The same ideas, under the names other tools use, so a reader can look them up:

| Here | Industry name | Tools |
|---|---|---|
| one gate on the merged tree, then fast-forward | merge queue, the "not rocket science" rule | GitHub merge queue, bors |
| versions set when landing, not per commit | release automation | release-please, changesets, release-plz (Rust) |
| skip a tree that already passed | build or test result caching keyed by inputs | Bazel, Nx, Turborepo |
| the API check before a published crate's version | semver linting | cargo-semver-checks |
