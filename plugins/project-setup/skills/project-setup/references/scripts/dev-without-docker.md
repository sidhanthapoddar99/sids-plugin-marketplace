# Dev mode without docker

The default dev mode for this project: **apps on host, databases in containers.** Faster iteration, hot reload, direct IDE debugger attach.

## Why

| Containerised dev | Apps-on-host + DBs in containers |
|---|---|
| Total parity with prod | Faster iteration |
| Slow file watching on bind-mounts (especially macOS) | Native file events |
| Complex debugger attach (port mapping, breakpoints) | IDE attaches directly to the local process |
| `docker compose restart` to pick up code changes | `--reload` / `bun dev` / `cargo-watch` natively |
| Same image runs in CI and dev | Different setup; rare drift |

For most personal projects the dev velocity wins. Production parity is enforced by CI building images and running tests against them; you don't need to develop against the image.

## How `./dev` arranges this

`./dev` (bare flow):

1. Brings up only `postgres + redis` via `docker compose -f docker/compose.database-only.yaml up -d`
2. Waits for healthchecks
3. Installs deps on host (`uv sync`, `bun install`, `cargo fetch`)
4. Runs migrations
5. Starts each application service as a host process with hot reload
6. Prefixes log streams so output is readable
7. `trap` kills all child processes on Ctrl-C

```bash
# (excerpt from a Topology 03 bare flow)
( cd apps/backend-rust   && cargo run -p api 2>&1 | prefix "rust    " "35" ) &
local rust_pid=$!

( cd apps/backend-python && uv run uvicorn app.main:app --reload \
    --host "${PYTHON_HOST}" --port "${PYTHON_PORT}" 2>&1 | prefix "python  " "33" ) &
local py_pid=$!

( cd apps/frontend && bun dev 2>&1 | prefix "frontend" "36" ) &
local fe_pid=$!

trap 'kill "$rust_pid" "$py_pid" "$fe_pid" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
```

## What stays in containers

- Postgres (and any other stateful service)
- Redis
- Seaweed / Meilisearch / Neo4j — anything that's an infra dep with state
- Optionally: an nginx for testing routing (or use Vite's proxy in dev and nginx only in prod)

## What runs on host

- Python backend (uvicorn / gunicorn with `--reload`)
- Rust backend (`cargo run` with `cargo-watch` if desired)
- Frontend (`bun dev`, `pnpm dev`)
- Test runners

## Reverse proxy in dev

Two options:

1. **Vite proxy** — `vite.config.ts` proxies `/api/*` to the backend's host port. The frontend talks to the Vite dev server (`http://localhost:5173`), Vite forwards `/api/*` requests. CORS-free.
2. **Local nginx in container** — `docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up nginx` brings up nginx exposing port 80, routing `/api/*` to backend's host port (via `host.docker.internal` on Mac/Windows, or `--add-host=host.docker.internal:host-gateway` on Linux).

Default to (1) — simpler, no extra container.

## Frontend talks to backend

In dev, the frontend's `vite.config.ts`:

```ts
export default defineConfig({
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: `http://localhost:${process.env.PYTHON_PORT ?? 8000}`,
        changeOrigin: true,
      },
    },
  },
});
```

In prod, nginx (inside its container) routes `/api/*` to the `backend` service via the internal compose network. Same URL contract — only the proxy changes.

## When this doesn't fit

- **Heavy native deps** that are easier to install in a container than on host (e.g. specific glibc, exotic GPU libs) — containerise that service
- **Cross-platform team** where some can't easily install the local toolchain — provide a containerised fallback (`./dev container-mode`) but keep host as the default
- **Operating against the prod image** as a debugging step — use `compose.yaml + compose.dev.yaml` for that one session

## Anti-patterns

- Bind-mounting source code into a container in dev — slow file events, complex permissions; just run on host
- Different env variables for "in-container" vs "on-host" dev — too easy to drift; standardise on the env contract
- Skipping healthcheck waits — race conditions ("postgres not ready" errors on first run)
- Letting one team member run all-on-host and another all-in-containers without a defined toggle — fragments setups
