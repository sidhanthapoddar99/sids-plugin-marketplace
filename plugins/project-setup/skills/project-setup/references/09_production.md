# Production — what makes the stack fit to run

`compose.base.yaml` is prod. It carries the prod settings; modifiers add exposure and nothing else. This page is what those settings are, how a deploy runs, and how an operator tells a healthy stack from a sick one. Serving per language: `06_backend.md`. Security: `07_security.md`. Template: `template/docker/compose.base.yaml`.

## What every service in base carries

| Setting | Rule |
|---|---|
| `restart: unless-stopped` | Every long-running service. `on-failure` for one-shot jobs. Never `no` in prod. |
| `healthcheck` | Every app, proving readiness, with `start_period` covering boot (migrations, model load). Backend examples use `/ready`; the readiness budget must cover expected startup. Engines: `pg_isready`, `redis-cli ping`, a cypher ping. |
| `depends_on: condition: service_healthy` | Apps on engines. Never a bare `depends_on`: started is not ready. |
| `stop_grace_period` | ≥ the app's graceful timeout (`gunicorn --graceful-timeout 30` → `35s`). Otherwise every deploy SIGKILLs mid-drain. |
| `deploy.resources.limits` | `memory` above all: an unbounded leak takes the host down, a bounded one restarts alone. `cpus` sized with the worker count. Engines get deliberately higher limits; never starve the database. |
| `logging` | stdout and stderr only, JSON in prod, level from `config.yaml` (`config.local.yaml` for dev). Never a file inside the container. No secret, token or body with PII. |
| `x-defaults` anchor | The repeated block (`restart`, `logging`, `stop_grace_period`) written once at the top of the file and merged into every service with `<<: *defaults`. `${VAR}` for values, anchors for structure. |

Internal ports are literals (`api:8000`). Only published host ports vary, and only through a modifier.

## Health, two questions

| Endpoint | Question | Failing means |
|---|---|---|
| `/health` | Is the process alive? Cheap: the event loop turns. | Restart the container. |
| `/ready` | Can it serve now? Database reachable, migrations applied, model loaded. Returns `503` with the failing check named. | Pull from the load balancer. Do not restart. |

Compose healthchecks gate startup readiness and dependencies, so backend checks read `/ready`. `/health` remains the separate liveness signal. A host proxy or load balancer also reads `/ready`. Standalone Compose reports an unhealthy check; an automatic restart policy for unhealthy services is a separate operator decision.

## The deploy

For central Traefik, Cloudflare Tunnel, ngrok, or direct Nginx HTTP with optional TLS, see [HTTP and TLS deployment options](12_http-and-tls.md). Public port mappings alone do not enable TLS; choose the exposure and certificate setup for your deployment.

1. Set `TAG=auto` in the server's `.env`. The server builds every image from source, from a full git clone. No registry holds the images, and ctl never pulls or pushes one. Each service with `build:` says `pull_policy: never`, so a missing image is an error, never a download; `ctl check` proves it. ctl names the images `<product>/<app>:<commit>` (`acme/api:f5744bff`) after the checkout's commit, so each deploy keeps its own images. A build from a checkout with uncommitted changes is refused, because its images would carry a commit's name without matching it. `.env.template` lists the four forms beside `TAG`: `dev` for local builds, `auto`, a pinned commit or git tag, and `none`, which names the images `latest`. `ctl build` can build the images separately; `ctl up` also requires all selected and dependency image builds to succeed before activating containers. Never redeploy a moving `latest`; a tag is never repurposed, so production never uses `dev` or `none`.
2. Uncomment `PUBLIC_URL`, `HTTP_PORT` and `HTTPS_PORT` in `.env` (`02_env.md` rule 10), then `ctl up +public -y`, or `ctl up preset public -y`. Compose orders engines, schema one-shots and apps from `depends_on`. CTL checks the selected dependency closure against declared readiness checks and successful one-shot completion within a bounded budget. A build failure makes no activation call; an activation or readiness failure returns nonzero. `ctl up` without a modifier is local docker: the edge on the `/` owner's port, no public origin.
3. Migrations are never inside an app's boot, because a boot-time migration runs once per replica and once per restart, and N replicas racing `upgrade head` corrupt the version table. The step is a one-shot compose service (`migrate` in `compose.base.yaml`, `restart: "no"`) that every app `depends_on` with `condition: service_completed_successfully`, so it runs once per `up` whatever the replica count, inside the compose network, with no engine port published. `ctl db migrate` re-runs it by name. This step is the home of the rule; `06_backend.md` § Migrations points here.
4. Recover forward: a new commit, or a restore from backup. Rollbacks are off, and never cross a migration. Just before a deploy activates anything, ctl writes its commit to `DATA_DIR/deployed-commit`, because the migrate one-shot may change the data even when a later service fails. `ctl db migrate up` writes the record too. A later deploy whose commit is not ahead of the record is a rollback. `ROLLBACK=off`, the default and what an empty value means, refuses every rollback. `ROLLBACK=on` allows one only when no file under `MIGRATION_PATHS` (`apps/database`, an `[ADAPT]` knob in `_lib.sh`) differs between the two commits. Then `TAG=<old commit> ctl up preset public --no-build` starts the old images, if they still exist. ctl also refuses what it cannot compare: a pinned tag that names no commit, and a record whose commit the checkout lacks. The record follows the data: `ctl db backup` copies it into the backup, and `ctl db restore` puts it back, so the commit the backup's data matches may deploy again. A backup without a record leaves the current one, and the next deploy at or ahead of it migrates the restored data forward. A runtime failure after activation may leave a partially changed stack. CTL reports that failure; build-before-start is not atomic deployment rollback. Frozen builds support inspection but do not undo a database migration.
5. After a deploy is ready, ctl keeps the 2 newest deploy tags of each image it builds (`IMAGE_KEEP` in `_lib.sh`) and removes the rest with `docker image rm`. A local tag (`dev`, `dev-<name>`, `latest`) is neither counted nor removed, because each local build replaces it. It never removes an image a container uses, and never touches a repository it does not build. The output names what it removed. A failed removal is a warning; it never fails the deploy.

The startup worker uses `scripts/common/_compose_start.sh`. Its caller supplies a 120-second activation/readiness budget. Selected long-running services require readiness healthchecks; a clean exit counts as success only for explicitly declared schema one-shots or dependencies requiring `service_completed_successfully`. Foreground mode streams logs after readiness, reports unexpected stream/service exit and stops the selected stack on interruption. A detached success does not promise continued health.

For projects using Rust/WASM, follow `06_backend.md` § Rust and WASM: production selects a release profile explicitly and activates only compatible, completely built artifacts. Other projects gain no WASM tooling.

## The host

- `BASE_DIR` in `.env` is an absolute path on the host, such as `/DATA/AppData/<Company-Name>/<Project-name>`, so data, logs and backups live outside the checkout and survive a fresh clone (`02_env.md` § Host storage paths).
- The configured data, log and backup directories exist on the host with the right owner before the first `up`. `ctl setup env` creates them without installing a toolchain, because the server builds its images in Docker and needs no host toolchain. The container's UID must own the bind-mounted directory. On SELinux hosts the mount takes `:Z`. Never `chmod 777`.
- `.env`: `chmod 600`, owned by the deploy user. Never in the image; `COPY .env*` stays in image history forever.
- TLS terminates at a host proxy in front of the stack (outside this repo); `web` listens on 8080 as a non-root user. `client_max_body_size` and proxy timeouts in `nginx.conf.template`, aligned with the app's `--timeout`. Security headers and compression at the edge (`07_security.md`).
- Bind mounts, not named volumes: state is visible and backup-friendly. `BASE_DIR` moves all of it, and an absolute `DATA_DIR` moves the data alone to a fast disk or a tmpfs in CI, without touching a compose file.

## Reading a sick stack

| Tell | Meaning |
|---|---|
| `Up 12 seconds`, still, five minutes later | A crash loop. `docker inspect -f '{{.RestartCount}}' <ctr>` climbs; `ctl logs <svc> \| grep -i emerg` for nginx, the first traceback for an app. |
| healthy container, `/ready` returns 503 | A dependency is down or a migration is missing. Restarting the app will not fix it. |
| the edge answers, one prefix 502s | That upstream is down or renamed. `docker compose config` shows what `web` was told. |
| memory climbing between recycles | A leak the recycling hides. Bound it with the limit; fix it in the app. |

Frozen builds for a human pass: `ctl build save <target> <name>` freezes a build under `logs/test_build/build-<date>-<target>-<name>/` with branch, commit and date; `ctl build start` serves it. A person testing a state tests a build that cannot change under them.

## Observability

Not day one. In this order, as pain dictates: a `/metrics` endpoint (request rate, error rate, p50/p95/p99, worker memory, restart count) → tracing across services once there is more than one (OpenTelemetry) → error tracking → an external uptime pinger on `/health`. Each is an adapter in `core/`, swappable, opt-out enforced once.

## Multi-stack: several repos on one docker network

Rare. When two repos' stacks must reach each other by DNS:

- exactly one stack declares the network; every other joins it `external: true`
- service names are project-prefixed (`myapp-api`), because DNS is shared
- bring-up order is written in each README; `depends_on` cannot cross stacks
- nginx uses `resolver 127.0.0.11` and a variable in `proxy_pass`, so a down neighbour is a 502, not a crash loop
- dev configs never join the shared network; `ctl dev` must work with every other stack down
- across repos, the contract is a service name and its API, never a shared image: each repo builds its own images from source on the host, and none is pushed to a registry

## Checklist

Walk this before the first public deploy, and again when a new service joins. The first three rows are the verification floor growing up with the repo; the rest are the stack.

- [ ] `audit` and `build` are in `RUNGS` and in the `Gate ladder` row of `AGENTS.md`; the audit tools are in `.mise.toml` (`10b_static-checks.md`)
- [ ] the security review has been walked and its answers recorded (`10a_review.md`, `07_security.md`)
- [ ] git hooks are installed when more than one person commits (`additional-template/README.md`)
- [ ] production `CMD` (gunicorn, one process for Rust/Go/Node); worker count matches the CPU limit; recycling with jitter on Python
- [ ] the product has a version in the files `scripts/release/versions.sh` lists, and branches land through `ctl merge` (`15_releases.md`)
- [ ] every Rust or WASM image walks `16_rust-production.md` § Checklist: the release profile, `wasm-opt`, pinned tools, parallel stages, bounded caches
- [ ] `/health` and `/ready` exist; compose healthcheck with `start_period`; `depends_on: service_healthy`
- [ ] graceful shutdown: lifespan cleanup, `stop_grace_period` ≥ graceful timeout
- [ ] memory and CPU limits on every service; `restart: unless-stopped`
- [ ] logs to stdout, JSON, level from config, no secrets
- [ ] migrations as a pre-traffic step, one path chosen
- [ ] `TAG=auto` and `ROLLBACK=off` in the server's `.env`; the server builds every image from source, from a full clone; every built service says `pull_policy: never`
- [ ] the README's recovery line goes forward, never back: a new commit, or a restore from backup
- [ ] TLS at the host proxy; body size and timeouts aligned; security headers
- [ ] env files `chmod 600`; no `COPY .env*`; non-root user in every image
- [ ] every backend runs with `AUTH_ENABLED=TRUE`: compose states it as a literal, and a backend run outside a container gets it from `.env`, because the request checks cannot see a host proxy that adds no forwarding header (`14_development-sign-in.md`)
- [ ] no token, session or password exists for the reserved `default` user, and no migration updates its row
- [ ] `BASE_DIR` absolute in the host's `.env`; `DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` derived from it, or absolute on purpose; `ctl check` green
- [ ] `ctl setup env` run on the host; the data, logs and backup directories owned by the container's UID
