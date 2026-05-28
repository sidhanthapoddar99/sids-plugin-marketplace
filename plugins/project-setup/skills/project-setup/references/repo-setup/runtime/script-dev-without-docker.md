# `ctl dev` — apps on host, DBs in containers

The default dev mode: **apps run on the host (hot reload), only data services run in containers.** This is exactly what `ctl dev` does. Faster iteration, native file events, direct IDE debugger attach.

## Why host, not containerised apps

| Containerised apps in dev | Apps on host (`ctl dev`) |
|---|---|
| Total parity with prod | Faster iteration |
| Slow file watching on bind-mounts (esp. macOS) | Native file events |
| Complex debugger attach (port mapping) | IDE attaches directly to the local process |
| `docker compose restart` to pick up changes | `--reload` / `bun dev` / `cargo-watch` natively |

Production parity is enforced by CI building images and by `ctl up app edge --config=prod` running them — you don't need to *develop* against the image. When you do want the containerised stack, that's `ctl up app` (or `ctl up app edge --config=prod`), not `ctl dev`.

## What `ctl dev` arranges

1. Brings up its **data-container deps** (`postgres`, `redis`) via `ctl up` (thin `docker compose up -d`) and waits for healthchecks.
2. Starts each **application** service as a **host process** with hot reload.
3. Multiplexes their output into readable, per-service panes.
4. Stops everything cleanly on Ctrl-C / quit.

Steps 2–4 are delegated to a process runner — **don't hand-roll PID juggling** (see `references/repo-setup/scripts/global-wrapper-dispatcher.md` § "Delegate"). Default `process-compose`; `mprocs` as a lighter option; a bash `trap` only as a 1–2-process fallback.

### Preferred: `process-compose.yaml`

```yaml
processes:
  backend:
    command: "uv run uvicorn app.main:app --reload --port ${PYTHON_PORT:-8000}"
    working_dir: "apps/backend"
    readiness_probe: { http_get: { host: localhost, port: 8000, path: /health } }
  frontend:
    command: "bun dev"
    working_dir: "apps/frontend"
    depends_on: { backend: { condition: process_healthy } }
```

`ctl dev` runs all of these; `ctl dev backend` runs just one. `depends_on` orders the host processes; the data-container auto-up in `cmd_dev` orders the containers before them. That is the dependency enforcement — declare it, let the runner honour it.

### Fallback: bash `trap` (`scripts/dev-host.sh`, ≤ 2 processes)

```bash
prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }

( cd apps/backend  && uv run uvicorn app.main:app --reload --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
```

Past two processes (or once you want readiness ordering and a TUI), switch to `process-compose`.

## What stays in containers (brought up by `ctl up`)

- Postgres and any other stateful service
- Redis
- Seaweed / Meilisearch / Neo4j — infra deps with state
- Optionally an nginx for testing routing (or use Vite's proxy in dev, nginx only in prod)

## What runs on host (started by `ctl dev`)

- Python backend (uvicorn / gunicorn with `--reload`)
- Rust backend (`cargo run`, `cargo-watch`)
- Frontend (`bun dev`, `pnpm dev`)
- Test runners

## Reverse proxy in dev

1. **Vite proxy** (default) — `vite.config.ts` proxies `/api/*` to the backend's host port, read from env. CORS-free; no extra container. See `references/architecture/frontend/vite-proxy-nginx-pair.md`.
2. **Local nginx container** — `ctl up edge` brings up nginx routing `/api/*` to the backend (via `host.docker.internal`). Only if you need to exercise the prod-like routing in dev.

In prod (`ctl up app edge --config=prod`), nginx/traefik routes `/api/*` to the `backend` service over the compose network — same `/api/*` contract, only the proxy changes.

## When host-mode doesn't fit a service

- **Heavy native deps** easier to install in a container (exotic glibc, GPU libs) — containerise *that one service* (`docker compose -f docker/compose.yaml up -d <svc>`, or give it its own profile), keep the rest on host.
- **Cross-platform team** where some can't install the toolchain — provide the containerised path via `ctl up app edge --config=prod` / `ctl up app`, but keep host as the `ctl dev` default.

## Anti-patterns

- Bind-mounting source into a container in dev — slow file events, permission pain; run on host.
- Different env vars for in-container vs on-host dev — drift; standardise on the env contract (`references/repo-setup/env-and-config/env-precedence.md`).
- Skipping healthcheck waits — race conditions ("postgres not ready") on first run.
- Re-implementing a supervisor in `ctl` — delegate to `process-compose`/`mprocs`.

## See also

- `references/repo-setup/scripts/global-wrapper-dispatcher.md` — `ctl dev` / `ctl up [profile…] [--config=…]`
- `references/repo-setup/scripts/three-startup-paths.md` — the three documented ways to start
- `references/architecture/frontend/vite-proxy-nginx-pair.md` — dev proxy → prod nginx
