# ctl tooling tests

Frontend proxy tests use the installed Vite CLI and Node when available, with real loopback HTTP/WebSocket servers. UI plugins are stubbed; these tests verify routing, HMR delivery, public environment boundaries and production config evaluation, not React rendering. Compose tests render the self-contained base and check the dev preset's service subset and loopback-only exposure without starting containers.

These tests verify the shipped ctl shell library using temporary environment files. They belong to project-setup itself and are not copied into generated applications.

From the marketplace repository root, with Python 3 and pytest installed:

```sh
python3 -m pytest plugins/project-setup/skills/project-setup/tests/ctl -q
```

Run the suite on Linux or WSL with Bash, util-linux (`setsid`, `flock`, `taskset`), GNU coreutils, `curl` and `jq`. No Docker daemon or application dependencies are needed. Tests exercise real shell workers and isolated child processes; temporary directories contain all test storage.

- Environment, credentials and storage tests execute the real template helpers.
- Development tests launch isolated processes and HTTP probes to check readiness, interruption and owned-group cleanup.
- Rust dev cleanup tests use isolated generated build trees and configured log directories to check removal, preservation and refusal of unsafe targets.
- Setup uses executable doubles for fresh mise installation and activation; the Cargo workspace test also invokes real Cargo offline when available.
- Production startup, administration and restore tests use recording Docker/database shims. They verify ordering, selection and failure propagation without deploying or restoring a live database.
- Compose rendering tests use the real Docker Compose CLI when available and skip explicitly when it is absent. Cargo availability skips are also reported. These tests validate configuration without starting containers.
- Optional WASM behavior is guidance in `references/06_backend.md`; no WASM watcher or target is installed or exercised by the base suite.
- Stop tests use real isolated process groups and a recording Docker shim to check ownership, descendants, graceful cleanup, ordering, repeated calls and failures. They do not stop live project containers.
- `ctl setup env` tests run the real setup worker with recording doubles for mise, the package managers and lefthook, and prove that it installs nothing, that `ctl setup` runs the same env step first, and that help lists it. Storage tests resolve the shipped `BASE_DIR` block, an absolute root and shell overrides; a Compose test renders the same mount through `ctl` and through plain `docker compose`.
- Env merge tests (`test_env_merge.py`) run the real setup worker on fixture env files. They check that a key the template gains lands in its section, that values survive byte for byte, that a local comment stays with its key, that a key only `.env` has goes to the last section and is named, that a duplicate key stops setup, that a failed write leaves `.env` whole beside `.env.bak`, and that a second run changes nothing. A pseudo-terminal answers the removal question with yes, no and Enter; a run with no terminal and a run with `--remove-unlisted` never ask. No output may show a planted value.
- Data-core tests (`test_dev_data_core.py`) run the real `ctl` with a stateful recording Docker shim and a pseudo-terminal. They check that a running core is reused and never restarted, the start prompt and its no-terminal forms, migrations on every `ctl dev`, and that `ctl dev stop` keeps the core while `--all` stops it.
- Development sign-in tests check the `AUTH_ENABLED` key, the Compose literal, the reserved-user migrations and the reserved id in both example backends, and run the examples' auth-rule suites in scratch folders: Python with the suite's own interpreter, Rust with real Cargo offline when available (skipped explicitly otherwise).
- Help tests (`test_help_wrap.py`) run the real `ctl` in a pseudo-terminal of a set width, with colors on. They check that no help line passes the width, that folding keeps every word, that a row continues under its text, and that a pipe or a terminal under 40 columns gets the text as written. They also check each folding rule on short texts, a moved block of lines included.
- `test_template_copy.py` checks `scripts/template.sh copy` and `verify`, the `template core` rule of `ctl check`, and the install hints of `require_tools`. After any change to a file in `template/scripts/common/`, run `bash tests/ctl/template_core_manifest.sh --write` from the skill folder, because the suite fails while the shipped manifest disagrees with the helpers.

The controller, Rust watcher and development preflight tests use Bun (and Watchexec for watching):

```sh
bun test plugins/project-setup/skills/project-setup/tests/ctl/*.test.ts
```

They use temporary projects and real kernel locks, processes and file watching.
Preflight tests use package-manager doubles to verify configuration failures,
locked synchronization and failure-before-launch without installing application dependencies.

- Worktree tests (`worktree.test.ts`, `worktree-safety.test.ts`) build throwaway git repositories from the template in the system temp folder, with an isolated git configuration and a stand-in docker. They prove `ctl worktree` create, list, remove and trim, every refusal, a slot's `.env`, the busy check, the trim by age, the main-tree guard and the physical `CTL_ROOT`. They need git 2.38 or later and `flock`, and no Docker daemon.
- Gate and test-runner tests (`gate-modes`, `test-settings`, `gate-lock` and `gate-rungs`) use a throwaway copy of `ctl` and `scripts/` with stand-in rungs, tools and `systemd-run`, and a private lock file. They need git, `flock` and `taskset`.
The existing Python authoring suite above remains separate from shipped CTL scripts.
