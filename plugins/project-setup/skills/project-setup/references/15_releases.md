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

What counts as a change is mechanical: a part whose shipping paths the branch changed gets a patch release. Tests, fixtures and Markdown ship nothing, so a branch that changes only those, or only tooling, ships no version, because people receive nothing new. The minor and major numbers are the person's call, given as `ctl merge <branch> --minor=<part>` or `--major=<part>` (the part may be left out when the repo has one), because only a person knows whether an update adds or breaks.

## `ctl merge <branch>`

The one way work reaches the default branch. In the worktree that holds `<branch>` it:

1. merges the default branch into `<branch>` when the branch does not already contain it. A conflict stops the run with nothing half merged;
2. runs the version step, `scripts/release/versions.sh`, and commits what it sets as `Release: <versions>`;
3. runs one gate, `ctl gate --delta <default branch>`, on the merged tree, with `CTL_MERGE=1` in its environment;
4. fast-forwards the main tree's default branch to `<branch>`, and creates the tag of each part whose version is a git tag.

It never pushes, never rewrites a commit and fast-forwards only. `--dry-run` prints the plan and the versions it would set.

Why one command instead of steps in `AGENTS.md`:

- Two branches that each passed the gate can still break each other, so the gate must run on the merged tree. Running it there once, and fast-forwarding, means the default branch holds exactly the tree that passed. A gate before the merge and another after it is the same check twice.
- The gate records each tree it passed (`10d` § One run per tree), so `ctl merge` on a branch whose merged tree already passed costs no second run.
- A rule an agent must remember drifts; a rule `ctl` runs does not. A version bump in every commit, a forgotten bump, and a gate run three times per merge are each a habit that comes back after it is fixed by hand.

`CTL_MERGE=1` lets a project make a check strict only at merge time. Studio's engine ledger is the example: on a branch a changed engine is reported, and under `ctl merge` it must be recorded.

## The version step

`template/scripts/release/versions.sh` sets versions part by part. A part is something people receive with its own version: a product, a service, a package, a CLI, a WASM module. Its `[ADAPT]` list `VERSION_PARTS` holds one line per part, `<part> <where> [<path that ships it>…]`. The paths default to the folder of the part's manifest.

| Where the version lives | Write it as | What the step reads and writes |
|---|---|---|
| `package.json` | `web apps/web/package.json` | the top-level `"version"` |
| `pyproject.toml` | `api apps/api/pyproject.toml` | `version` under `[project]` |
| `Cargo.toml` | `engine apps/engine/Cargo.toml` | `version` under `[package]` or `[workspace.package]` |
| a `VERSION` file | `worker apps/worker/VERSION` | the file's one line, `x.y.z`, for any language |
| a git tag, as a Go module's | `cli tag:apps/cli/v apps/cli` | the newest tag `apps/cli/vx.y.z`; with none yet, it starts from `0.0.0`. `ctl merge` creates the next tag on the landed commit |
| one version in several manifests | `product apps/api/pyproject.toml,apps/web/package.json apps` | every listed manifest, which must agree |

The cases the step covers:

- **No version yet.** An empty `VERSION_PARTS` sets none, and `ctl merge` adds no commit. A repo that publishes nothing can stay this way.
- **One version.** One line. `--minor` and `--major` need no part name.
- **Several parts.** Each moves only when the branch changes one of its own paths, so a branch that touches the API raises the API and leaves the web app alone.
- **A version raised by hand** on the branch is kept and printed with `(raised on the branch)`.
- **Lock files** move with their manifest, because a locked install refuses a lock that disagrees: `cargo update --workspace --offline` for `Cargo.lock`, `uv lock --offline` for `uv.lock`, and `npm install --package-lock-only --offline` for `package-lock.json`. `bun.lock` records no workspace version, so Bun needs none. Each lock is the nearest one at or above the manifest.
- **A version the step cannot read**, such as a `pyproject.toml` with `dynamic = ["version"]`, stops the step by name. Such a version usually comes from git tags, so list the part as `tag:<prefix>`.

A part whose version moves on another trigger extends this step and records the extension in `AGENTS.md` § Exceptions. The shape Studio uses for its document engines:

| Part | Trigger | What the step writes |
|---|---|---|
| each engine | its input hash differs from its ledger entry | the next patch version in `Cargo.toml` and the lock, a `Compatible` migration step, the ledger entry, the release's baseline fixtures |
| the product | shipped code changed, or any engine moved | the next patch version, or the part `--minor`/`--major` names |
| an engine's major version | raised by hand, with its own conversion step | kept, and recorded |

The extension keeps the rule: each trigger is a fact the code can read, so no agent decides when a version moves.

## Packages

- Keep one version per workspace, and list the workspace as one part. A Rust workspace sets `version` once in `[workspace.package]`, and members say `version.workspace = true`. A crate that never leaves the repo sets `publish = false`.
- Pin shared dependencies once in `[workspace.dependencies]`, and in a JS group every manifest names the same version (`04_stack.md`).
- Commit every lockfile: `Cargo.lock`, `bun.lock`, `uv.lock`, `package-lock.json`, `go.sum`. A release builds from the lock, so two builds of one commit get the same dependencies.
- A published crate runs `cargo semver-checks` before its version is set, because it reads the public API and says whether the change is major. Choose `--major=<part>` when it says so.
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
