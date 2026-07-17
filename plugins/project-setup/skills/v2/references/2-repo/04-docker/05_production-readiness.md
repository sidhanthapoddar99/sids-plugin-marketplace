# Production readiness checklist

The "before you deploy" list — everything around the app server that separates a dev stack from a production-grade one: health checks, graceful shutdown, restart policy, resource limits, logging, migrations-on-deploy, reverse-proxy hardening, and observability. The **per-language worker model** (gunicorn workers, recycling, timeouts) is owned by `references/3-app/backend/serving.md` — cited by link below, not restated here.

## Health checks — liveness vs readiness

Two distinct endpoints, two distinct questions:

| Endpoint | Question | Failing means |
|---|---|---|
| **Liveness** (`/health` or `/healthz`) | "Is the process alive?" | Restart the container |
| **Readiness** (`/ready` or `/readyz`) | "Can it serve traffic right now?" (DB reachable, model loaded, migrations applied) | Pull from load balancer, don't restart |

```python
# apps/backend/app/health.py
from fastapi import APIRouter, Response

router = APIRouter()

@router.get("/health")
async def liveness():
    # Cheap — just "the event loop is turning"
    return {"status": "ok"}

@router.get("/ready")
async def readiness(response: Response):
    # Real dependency checks
    checks = {
        "postgres": await ping_postgres(),
        "redis": await ping_redis(),
    }
    if not all(checks.values()):
        response.status_code = 503
    return {"status": "ok" if all(checks.values()) else "degraded", "checks": checks}
```

Compose / nginx / Traefik use these:

```yaml
# docker/compose.prod.yaml
services:
  backend:
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8000/health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 30s        # grace for slow startup (migrations, model load)
```

`start_period` matters — without it, a service that takes 20s to boot gets marked unhealthy and restarted in a loop.

## Graceful shutdown

On `SIGTERM` (what `docker stop` / orchestrator rollout sends), the app must:

1. Stop accepting **new** connections
2. Finish **in-flight** requests (up to `graceful-timeout`)
3. Close DB / redis pools cleanly
4. Exit 0

Gunicorn handles 1–2 via `--graceful-timeout` (worker model owned by `references/3-app/backend/serving.md`). For app-level cleanup (closing pools), use lifespan hooks:

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    await redis.connect()
    yield                         # app runs
    await db.disconnect()         # SIGTERM → cleanup
    await redis.disconnect()

app = FastAPI(lifespan=lifespan)
```

Set `stop_grace_period` in compose to ≥ gunicorn's `graceful-timeout`:

```yaml
services:
  backend:
    stop_grace_period: 35s       # > gunicorn --graceful-timeout 30
```

Otherwise the orchestrator SIGKILLs mid-drain and you drop in-flight requests on every deploy.

## Restart policy

```yaml
services:
  backend:
    restart: unless-stopped       # dev + single-VM prod
    # OR for swarm/k8s, the orchestrator's restart policy governs
```

- `unless-stopped` — restart on crash, but stay down if you explicitly stopped it
- `on-failure` — restart only on non-zero exit (good for one-shot jobs)
- Never `no` for a long-running service in prod

## Resource limits

```yaml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          memory: 256M
```

- **Set memory limits** — an unbounded leak takes down the whole host otherwise. With a limit, the container OOMs alone and restarts.
- **Match worker count to CPU limit** — owned by `references/3-app/backend/serving.md`.
- Stateful services (postgres) need higher, deliberately-chosen limits — don't starve the DB.

## Logging

- **Log to stdout/stderr**, not files. The orchestrator / `docker logs` / log shipper captures the stream. (12-factor.)
- **Structured logs** (JSON) in prod for machine parsing; pretty logs in dev.
- Set log level via env (`LOG_LEVEL`), default `info` in prod, `debug` in dev (`config.local.yaml`).
- Don't log secrets, tokens, full request bodies with PII.

```python
# stdout, structured, level from env
import logging, sys, os
logging.basicConfig(
    stream=sys.stdout,
    level=os.environ.get("LOG_LEVEL", "info").upper(),
    format='%(asctime)s %(levelname)s %(name)s %(message)s',
)
```

## Migrations on deploy

Which run model applies — entrypoint-migrates (single replica) vs one-shot (N replicas) vs neutral `apps/db` owner — is owned by `references/3-app/backend/migrations.md`; the single-replica entrypoint recipe by `references/3-app/backend/alembic-recipe.md` § "Docker entrypoint — the container migrates itself". This file owns the multi-replica **one-shot** mechanics: never let N replicas race `upgrade head` on boot — run migrations once, as a gate the app `depends_on`:

```yaml
# docker/compose.prod.yaml — a one-shot migrate service
services:
  migrate:
    build: ../apps/backend
    command: ["alembic", "upgrade", "head"]
    env_file: [../.env.production]
    depends_on:
      postgres:
        condition: service_healthy
    restart: "no"
  backend:
    depends_on:
      migrate:
        condition: service_completed_successfully
```

`ctl up prod` or CI runs migrate → waits for success → starts/rolls the app.

## Reverse proxy hardening (nginx / Traefik)

- TLS termination at the edge (Traefik with Let's Encrypt, or nginx + certbot)
- Request body size limit (`client_max_body_size`) — don't let a 10 GB upload OOM you
- Timeouts (`proxy_read_timeout`) aligned with gunicorn `--timeout`
- Rate limiting at the edge for public endpoints
- Security headers (HSTS, X-Content-Type-Options, etc.)
- Gzip / brotli for text responses

(The `/api/*` routing contract and expose posture are owned by `references/2-repo/deployment/proxy-and-exposure.md`.)

## Observability (the next step, not day-one)

When the project graduates beyond "it runs":

- **Metrics** — Prometheus scrape endpoint (`/metrics`), or push to a hosted collector. Watch: request rate, error rate, p50/p95/p99 latency, worker memory, restart count.
- **Tracing** — OpenTelemetry spans across services (especially Layout 02 multi-backend).
- **Error tracking** — Sentry (backend DSN + frontend `VITE_SENTRY_DSN`).
- **Uptime** — external health-check pinger hitting `/health`.

Don't build all of this on day one. Add metrics first (cheapest signal), tracing when you have multiple services, the rest as pain dictates.

## Pre-deploy checklist (copy into the repo)

```
[ ] App server uses production CMD (gunicorn, not uvicorn --reload)
[ ] Worker count matches CPU limit; recycling (--max-requests + jitter) on for Python
[ ] /health (liveness) + /ready (readiness) endpoints exist and are wired into compose healthcheck
[ ] Graceful shutdown: lifespan cleanup + stop_grace_period ≥ graceful-timeout
[ ] Memory + CPU limits set on every service
[ ] restart: unless-stopped on long-running services
[ ] Logs go to stdout, structured, level from env, no secrets
[ ] Migrations run as a separate pre-traffic step, not in app startup
[ ] TLS at the edge; body size limit; proxy timeouts aligned
[ ] .env.production exists, chmod 600, not committed; secrets generated not invented
[ ] Bind-mount data dirs exist on the host (mkdir -p) with correct ownership
[ ] A rollback path exists (previous image tag, or git revert + redeploy)
```

The skill can drop this checklist into `docs/` or the README's Deploy section.

## Anti-patterns

- Running migrations in app startup with N replicas — migration races
- No readiness check — LB sends traffic to a booting/migrating instance
- No memory limit — one leak takes down the host
- `docker stop` with no graceful shutdown handling — drops in-flight requests every deploy
- Logging to files inside the container — lost on restart, fills the layer
- Building observability before the app is even stable — premature
- Secrets in the image layers (COPY .env) — they persist in image history forever

## See also

- `references/3-app/backend/serving.md` — worker / recycling / timeout detail (worker model owner)
- `references/2-repo/deployment/proxy-and-exposure.md` — `/api/*` contract, nginx/Traefik front door
- `references/2-repo/env-and-config/secrets-matrix.md` — prod secrets handling
- `references/2-repo/runtime/docker-overview.md` — the prod config (standalone)
- `references/3-app/backend/migrations.md` — the migration run-model decision this section implements
- `references/3-app/backend/alembic-recipe.md` — migration mechanics
