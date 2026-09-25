# ctl tooling tests

Frontend proxy tests use the installed Vite CLI and Node when available, with real loopback HTTP/WebSocket servers. UI plugins are stubbed; these tests verify routing, HMR delivery, public environment boundaries and production config evaluation, not React rendering. Compose tests render the self-contained base and check the dev preset's service subset and loopback-only exposure without starting containers.

These tests verify the shipped ctl shell library using temporary environment files. They belong to project-setup itself and are not copied into generated applications.

From the marketplace repository root, with Python 3 and pytest installed:

```sh
python3 -m pytest plugins/project-setup/skills/project-setup/tests/ctl -q
```

Run the suite on Linux or WSL with Bash, util-linux (`setsid`, `flock`), GNU coreutils, `curl` and `jq`. No Docker daemon or application dependencies are needed. Tests exercise real shell workers and isolated child processes; temporary directories contain all test storage.

- Environment, credentials and storage tests execute the real template helpers.
- Development tests launch isolated processes and HTTP probes to check readiness, interruption and owned-group cleanup.
- Rust dev cleanup tests use isolated generated build trees and configured log directories to check removal, preservation and refusal of unsafe targets.
- Setup uses executable doubles for fresh mise installation and activation; the Cargo workspace test also invokes real Cargo offline when available.
- Production startup, administration and restore tests use recording Docker/database shims. They verify ordering, selection and failure propagation without deploying or restoring a live database.
- Compose rendering tests use the real Docker Compose CLI when available and skip explicitly when it is absent. Cargo availability skips are also reported. These tests validate configuration without starting containers.
- Optional WASM behavior is guidance in `references/06_backend.md`; no WASM watcher or target is installed or exercised by the base suite.
- Stop tests use real isolated process groups and a recording Docker shim to check ownership, descendants, graceful cleanup, ordering, repeated calls and failures. They do not stop live project containers.

The controller, Rust watcher and development preflight tests use Bun (and Watchexec for watching):

```sh
bun test plugins/project-setup/skills/project-setup/tests/ctl/*.test.ts
```

They use temporary projects and real kernel locks, processes and file watching.
Preflight tests use package-manager doubles to verify configuration failures,
locked synchronization and failure-before-launch without installing application dependencies.
The existing Python authoring suite above remains separate from shipped CTL scripts.
