# App server + workers — production serving

How the backend actually runs in production: the **per-language worker model, worker recycling, and timeouts**. Dev uses a single hot-reload process (`uvicorn --reload`); production uses a process manager with multiple workers, recycling, and graceful shutdown. This is a decision the skill owns — it changes the Dockerfile `CMD`, the compose service, and resource sizing. (The broader pre-deploy checklist — health/readiness, limits, migrations-on-deploy — is L2: `references/2-repo/deployment/production-readiness.md`.)

## Python — gunicorn + uvicorn workers (FastAPI / Starlette)

The standard production combo for async Python: **gunicorn** as the process manager, **uvicorn workers** as the async ASGI runtime.

```bash
gunicorn app.main:app \
  --worker-class uvicorn.workers.UvicornWorker \
  --workers 5 \
  --max-requests 1000 \
  --max-requests-jitter 100 \
  --timeout 60 \
  --graceful-timeout 30 \
  --keep-alive 5 \
  --bind 0.0.0.0:8000 \
  --access-logfile - \
  --error-logfile -
```

### Worker count

Rule of thumb: **`(2 × CPU cores) + 1`**.

- 2 cores → 5 workers
- 4 cores → 9 workers

This is a *starting point* for CPU-bound + mixed workloads. For heavily I/O-bound async apps (most FastAPI services), each uvicorn worker handles many concurrent requests on its event loop, so you may need **fewer** workers than the formula suggests — sometimes `cores + 1`. Measure under load; don't cargo-cult the formula.

Drive it from env so it's tunable per deployment:

```bash
--workers ${WEB_CONCURRENCY:-5}
```

(`WEB_CONCURRENCY` is the conventional env var gunicorn reads automatically.)

### Worker recycling — the memory-leak guard

```
--max-requests 1000 --max-requests-jitter 100
```

Each worker is **restarted after handling ~1000 requests** (±100 jitter). Why:

- Long-running Python processes accumulate memory (fragmentation, C-extension leaks, cached objects). Recycling bounds the blast radius — a leaky worker is killed and replaced before it OOMs.
- **Jitter is essential** — without it, all workers hit 1000 simultaneously and restart together, causing a thundering-herd latency spike. Jitter staggers them.

Tune `max-requests` to your traffic: too low = constant churn (cold starts cost latency); too high = leaks grow. 1000–5000 is a common range.

### Timeouts

| Flag | Meaning | Typical |
|---|---|---|
| `--timeout` | Worker killed if a request takes longer (silent worker → restart) | 30–60s for APIs; higher for long uploads |
| `--graceful-timeout` | On shutdown/restart, how long to let in-flight requests drain before SIGKILL | 30s |
| `--keep-alive` | Seconds to hold an idle keepalive connection. Behind nginx, keep ≥ nginx's upstream keepalive | 5s |

### Preload — the trade-off

```
--preload
```

Loads the app **once in the master** before forking workers. Trade-off:

| `--preload` ON | `--preload` OFF (default) |
|---|---|
| Lower memory (copy-on-write shared pages) | Each worker loads independently |
| Faster worker spawn | Slower spawn |
| **No zero-downtime reload** (master holds the code) | Workers can be reloaded individually |
| Good for stable prod images | Good when you hot-reload workers |

Default to **`--preload` in containerised prod** (you redeploy the whole image anyway, so per-worker reload doesn't matter, and the memory saving is real). Skip it if you rely on `HUP`-signal worker reloads.

### Gunicorn config file (cleaner than CLI flags)

For anything beyond a couple of flags, use `gunicorn.conf.py`:

```python
# gunicorn.conf.py (next to pyproject.toml in the service folder)
import os

bind = f"0.0.0.0:{os.environ.get('PYTHON_PORT', '8000')}"
worker_class = "uvicorn.workers.UvicornWorker"
workers = int(os.environ.get("WEB_CONCURRENCY", "5"))
max_requests = int(os.environ.get("MAX_REQUESTS", "1000"))
max_requests_jitter = int(os.environ.get("MAX_REQUESTS_JITTER", "100"))
timeout = int(os.environ.get("WORKER_TIMEOUT", "60"))
graceful_timeout = 30
keepalive = 5
preload_app = os.environ.get("PRELOAD", "true").lower() == "true"
accesslog = "-"
errorlog = "-"
```

```bash
gunicorn app.main:app -c gunicorn.conf.py
```

### Dockerfile CMD

```dockerfile
# production CMD — NOT uvicorn --reload
CMD ["gunicorn", "app.main:app", "-c", "gunicorn.conf.py"]
```

Dev (`ctl dev` host run) uses `uvicorn --reload`; the image uses gunicorn. Two different entrypoints for two different jobs — don't ship `--reload` to prod. (Where this CMD sits in the multi-stage Dockerfile: `references/3-app/backend/app-skeleton.md`.)

### uvicorn-only alternative

For small services, gunicorn-less uvicorn with `--workers` works:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

But uvicorn's own multi-worker mode lacks gunicorn's recycling (`--max-requests`) and richer process management. **Prefer gunicorn + uvicorn workers for anything that needs recycling.**

## Rust — Axum / Actix

Rust async servers (Axum on Tokio) are **already multi-threaded** — one process saturates all cores via the Tokio runtime. No worker-process model needed.

```rust
// main.rs — Tokio multi-threaded runtime is the default with #[tokio::main]
#[tokio::main]
async fn main() {
    // axum::serve uses the multi-threaded runtime; one process, N worker threads
}
```

- **No `--workers` equivalent** — set Tokio worker threads if needed via `TOKIO_WORKER_THREADS` env (defaults to CPU count).
- **No recycling needed** — Rust doesn't leak the way long-running Python does. If you have a leak, fix it; don't paper over with restarts.
- Run **one container per service**, scale horizontally with replicas, not worker processes.
- Graceful shutdown: handle `SIGTERM`, stop accepting new connections, drain in-flight (`axum::serve(...).with_graceful_shutdown(...)`).

## Node — clustering / PM2

Node is single-threaded per process. To use all cores:

- **`node:cluster`** built-in, or
- **PM2** in cluster mode (`pm2 start app.js -i max`), or
- Run N container replicas behind the load balancer (preferred in containerised setups — let the orchestrator do the multiplexing rather than PM2 inside the container)

Default in a compose/k8s world: **one process per container, scale via replicas.** PM2-in-container fights the orchestrator.

## Go

Go's runtime is multi-threaded and handles concurrency natively (goroutines + `GOMAXPROCS`). One process per service, scale via replicas. No worker-process or recycling story needed.

## The cross-cutting rule

| Language | Production concurrency model |
|---|---|
| Python (sync or async) | Multiple worker **processes** (gunicorn) + recycling |
| Rust | One process, many **threads** (Tokio); scale via replicas |
| Node | One process per container; scale via **replicas** (not PM2-in-container) |
| Go | One process, goroutines; scale via **replicas** |

Python is the outlier that needs the worker-process + recycling machinery. The others scale by running more containers. The skill should know which model applies to the chosen backend.

## Compose wiring

The prod overlay sets the worker env and resource limits (the overlay itself and the exposure posture are owned at L2 — `references/2-repo/runtime/docker-overview.md`):

```yaml
# docker/compose.prod.yaml
services:
  backend:
    environment:
      WEB_CONCURRENCY: "5"
      MAX_REQUESTS: "2000"
      MAX_REQUESTS_JITTER: "200"
      PRELOAD: "true"
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
```

Match `WEB_CONCURRENCY` to the `cpus` limit — there's no point running 9 workers in a container limited to 2 CPUs.

## Anti-patterns

- Shipping `uvicorn --reload` to production — reload watches the filesystem, leaks memory, single-process.
- No worker recycling on a long-running Python service — slow memory creep → eventual OOM.
- `--max-requests` without `--max-requests-jitter` — synchronised restart storms.
- Worker count wildly mismatched to CPU limit (9 workers, 1 CPU) — context-switch thrash.
- PM2 cluster mode *inside* a container that the orchestrator also replicates — double multiplexing.
- Adding gunicorn worker recycling to a Rust/Go service — they don't have the leak problem; you're adding complexity for nothing.
- One giant worker with `--timeout 0` — a hung request blocks forever with no recovery.

## See also

- `references/2-repo/deployment/production-readiness.md` — the broader pre-deploy checklist (health, limits, migrations-on-deploy)
- `references/2-repo/runtime/docker-overview.md` — where the prod config (standalone) lives
- `references/2-repo/deployment/proxy-and-exposure.md` — nginx sits in front of these workers
- `references/3-app/backend/app-skeleton.md` — the Dockerfile these workers ship in
