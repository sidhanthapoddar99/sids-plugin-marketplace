# Production — what makes the stack fit to run

`compose.base.yaml` is prod. It carries the prod settings; modifiers add exposure and nothing else. This page is what those settings are, how a deploy runs, and how an operator tells a healthy stack from a sick one. Serving per language: `06_backend.md`. Security: `07_security.md`. Template: `template/docker/compose.base.yaml`.

## What every service in base carries

| Setting | Rule |
|---|---|
| `restart: unless-stopped` | Every long-running service. `on-failure` for one-shot jobs. Never `no` in prod. |
| `healthcheck` | Every app, hitting `/health`, with `start_period` covering boot (migrations, model load). Without it a service that boots in 20 s is restarted in a loop. Engines: `pg_isready`, `redis-cli ping`, a cypher ping. |
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

The compose healthcheck reads `/health`. A host proxy or load balancer reads `/ready`.

## The deploy

1. `ctl build` with an immutable `TAG` (a git sha or a semver) on images named `<product>/<app>` (`acme/api`). Never redeploy a moving `latest`; a tag is never repurposed.
2. `ctl up +expose_web -y`. The data core comes up and is waited on; migrations run once; then the apps.
3. Migrations are never on app boot. With one replica, `up.sh` runs `ctl migrate up` before the apps. With N replicas the same step is a one-shot compose service (`migrate`, `restart: "no"`) that the apps `depends_on` with `condition: service_completed_successfully`, because N replicas racing `upgrade head` corrupt the version table. Pick one per project and delete the other path.
4. Rollback is the previous `TAG`, or a `ctl build save` snapshot. A rollback path exists before the first deploy, not after the first incident.

## The host

- `data/` and `logs/` exist on the host with the right owner before the first `up`; `ctl setup` creates them. The container's UID must own the bind-mounted directory. On SELinux hosts the mount takes `:Z`. Never `chmod 777`.
- `.env.secrets`, `.env.data`, `.env.proxy`: `chmod 600`, owned by the deploy user. Never in the image; `COPY .env*` stays in image history forever.
- TLS terminates at a host proxy in front of the stack (outside this repo); `web` listens on 8080 as a non-root user. `client_max_body_size` and proxy timeouts in `nginx.conf.template`, aligned with the app's `--timeout`. Security headers and compression at the edge (`07_security.md`).
- Bind mounts, not named volumes: state is visible and backup-friendly. `${DATA_DIR}` moves it to a fast disk or a tmpfs in CI without touching a compose file.

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
- across repos, images are the contract: a child builds and pushes `:sha` and `:tag`; a consumer pins; a tag is never repurposed

## Checklist

- [ ] production `CMD` (gunicorn, one process for Rust/Go/Node); worker count matches the CPU limit; recycling with jitter on Python
- [ ] `/health` and `/ready` exist; compose healthcheck with `start_period`; `depends_on: service_healthy`
- [ ] graceful shutdown: lifespan cleanup, `stop_grace_period` ≥ graceful timeout
- [ ] memory and CPU limits on every service; `restart: unless-stopped`
- [ ] logs to stdout, JSON, level from config, no secrets
- [ ] migrations as a pre-traffic step, one path chosen
- [ ] immutable `TAG`; a rollback path
- [ ] TLS at the host proxy; body size and timeouts aligned; security headers
- [ ] env files `chmod 600`; no `COPY .env*`; non-root user in every image
- [ ] `data/` and `logs/` owned by the container's UID
