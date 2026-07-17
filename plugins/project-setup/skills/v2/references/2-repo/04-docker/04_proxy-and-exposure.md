# Proxy and exposure — the `/api/*` contract

Owns the front-door routing contract: every backend route lives under `/api/*`, Vite proxies it in dev, nginx routes it in prod, and the reverse proxy is the sole entry point. Same URL contract in both environments, so frontend code never knows which one it's in. The compose expose-tier mechanics (`compose.m.expose*.yaml`, the Traefik modifier) are owned by `references/2-repo/runtime/docker-overview.md`; this file owns the *posture* those tiers implement.

## The `/api/*` rule

- Backend mounts routes under `/api/<endpoint>` (e.g. `/api/users`, `/api/sessions`)
- Frontend code calls `/api/<endpoint>` (no host, just the path)
- Vite proxies `/api/*` in dev, nginx routes `/api/*` in prod
- All other paths (`/`, `/login`, `/dashboard`) are the SPA

This single rule is what makes the Vite-proxy / nginx pair below work.

### Backend implementation

FastAPI:

```python
from fastapi import FastAPI, APIRouter

app = FastAPI(root_path="/api")    # mounts everything under /api

users_router = APIRouter(prefix="/users", tags=["users"])

@users_router.get("")
async def list_users(): ...

app.include_router(users_router)
# Result: GET /api/users
```

Or, mount manually:

```python
api = APIRouter(prefix="/api")
api.include_router(users_router, prefix="/users")
app.include_router(api)
```

Axum (Rust):

```rust
let api = Router::new()
    .nest("/users", users::routes())
    .nest("/sessions", sessions::routes());

let app = Router::new()
    .nest("/api", api);
```

### Frontend implementation

```ts
// apps/frontend/src/lib/api.ts
export const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "/api";

export async function fetchJSON<T>(path: string): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

// usage
const users = await fetchJSON<User[]>("/users");   // → GET /api/users
```

`VITE_API_BASE_URL=/api` in dev **and** prod — same value. Only the proxy / nginx routing differs underneath.

## Dev — Vite proxy

`apps/frontend/vite.config.ts`:

```ts
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const backendPort = env.PYTHON_PORT ?? "8000";

  return {
    plugins: [react()],
    resolve: {
      alias: { "@": path.resolve(__dirname, "src") },
    },
    server: {
      port: 5173,
      proxy: {
        "/api": {
          target: `http://localhost:${backendPort}`,
          changeOrigin: true,
        },
      },
    },
  };
});
```

Frontend code calls `/api/users` — Vite intercepts and forwards to `http://localhost:8000/api/users`. No CORS, no `VITE_API_URL` per environment.

> Vite has no server runtime, so the proxy target lives in build/dev env that is effectively client-adjacent. With Next.js the equivalent proxy (`next.config` `rewrites()`) runs server-side and can use server-only env. See the Vite-vs-Next env-split comparison in `references/2-repo/env-and-config/frontend-env-isolation.md`.

## Prod — nginx routing

```nginx
# infra/nginx/nginx.conf
events { worker_connections 1024; }

http {
  include /etc/nginx/mime.types;
  sendfile on;

  upstream backend {
    server backend:8000;            # compose service name
  }

  server {
    listen 80;
    server_name _;

    # API routes to backend container
    location /api/ {
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_read_timeout 60s;
    }

    # WebSocket — y-sweet, server-sent events, etc.
    location /ws/ {
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }

    # Frontend static + SPA fallback
    location / {
      root /usr/share/nginx/html;
      try_files $uri $uri/ /index.html;
    }
  }
}
```

The frontend bundle is built into `/usr/share/nginx/html` by the frontend's Dockerfile; nginx serves it and proxies `/api/*` to the backend container.

> **In-stack only.** The literal `upstream`/`proxy_pass` above resolves `backend` **once at nginx startup** — safe here because `depends_on` guarantees the container exists. If nginx proxies to a service in *another* compose stack (shared network across repos), a down upstream makes nginx crash-loop with `[emerg] host not found in upstream`. Use the `resolver` + variable `proxy_pass` pattern in `references/2-repo/runtime/multi-stack.md` instead.

### Frontend Dockerfile (multi-stage)

```dockerfile
# apps/frontend/Dockerfile
FROM oven/bun:1 AS deps
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile

FROM oven/bun:1 AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG VITE_API_BASE_URL=/api
ARG VITE_APP_ENV=production
RUN bun run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY ../../infra/nginx/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

## Same contract, two implementations

| Path | Dev | Prod |
|---|---|---|
| `GET /api/users` (from browser) | Vite intercepts → `localhost:8000/api/users` | nginx in container → `backend:8000/api/users` |
| `GET /` (SPA) | Vite serves `index.html` from `apps/frontend/` | nginx serves `index.html` from `/usr/share/nginx/html` |
| WebSocket `/ws/sync` | Vite proxies | nginx with `Upgrade` headers |

Frontend code is identical in both. `/api/...` works everywhere.

## Multi-frontend variant

When multiple frontends call the same API, each can use the same `/api/*` prefix. nginx routes by host or path:

```nginx
# host-based routing
server {
  server_name admin.example.com;
  location /api/ { proxy_pass http://admin_backend; }
  location /     { root /usr/share/nginx/html/admin; try_files $uri /index.html; }
}

server {
  server_name app.example.com;
  location /api/ { proxy_pass http://app_backend; }
  location /     { root /usr/share/nginx/html/app; try_files $uri /index.html; }
}
```

Or path-based:

```nginx
server {
  location /api/admin/ { proxy_pass http://admin_backend; }
  location /admin/     { root /usr/share/nginx/html/admin; try_files $uri /admin/index.html; }
  location /api/       { proxy_pass http://app_backend; }
  location /           { root /usr/share/nginx/html/app; try_files $uri /index.html; }
}
```

## Exposure posture

The reverse proxy is the **sole entry point**. The base compose is port-less; you opt into exactly the exposure you need, and the safe default publishes only the edge (nginx), keeping the apps and data core unreachable from the host.

| Posture | What's reachable | When |
|---|---|---|
| Edge-only (default) | nginx only | normal run — everything behind the reverse proxy |
| Data exposed | + postgres/redis on host | host-run dev app reaching the containerised data core |
| All exposed | every service | debugging — talk to a service directly, bypassing nginx |
| Traefik ingress | edge joins a shared external Traefik net | production ingress behind a shared Traefik |

These postures are implemented by the tiered `expose` / `expose_data` / `expose_all` / `traefik` compose **modifiers** — the file bodies, the `ctl up --modifier` mechanics, and the rationale for tiering live in `references/2-repo/runtime/docker-overview.md`. Don't restate them here; this file only fixes the posture (edge is the front door, everything else opts in).

## When the `/api/*` rule bends

- **Reverse proxy headers** — backend must read `X-Forwarded-*` to know the real origin (set by nginx/Traefik)
- **WebSockets** — `/ws/*` is a separate prefix; nginx needs the `Upgrade` headers
- **CDN-fronted assets** — static asset URLs may live on a different host (CDN), but that's the SPA's problem, not the API routing

## Anti-patterns

- Hardcoding `http://localhost:8000` in frontend code — breaks in prod
- Different `VITE_API_BASE_URL` per environment — defeats the proxy
- Backend routes at root (`/users`, `/sessions`) — collides with SPA paths
- Different prefixes per endpoint (`/api/v1/...`, `/admin/...`) — pick one rule
- Mounting docs (Swagger / `/docs`) at root — put them under `/api/docs` so they follow the same routing
- Forgetting WebSocket upgrade headers in nginx — sync silently breaks
- Proxying `/api` to a host different from where nginx serves — CORS reappears
- Serving the frontend from the backend (e.g. FastAPI + StaticFiles) — slower in prod, mixes concerns; use nginx
- A literal `proxy_pass` to a service in **another** compose stack — startup-time DNS resolution crash-loops when that stack is down; see `references/2-repo/runtime/multi-stack.md`
- Publishing every service by default — over-exposes; keep the edge the sole entry point

## See also

- `references/2-repo/runtime/docker-overview.md` — expose-tier modifiers + Traefik modifier mechanics
- `references/2-repo/runtime/multi-stack.md` — cross-stack nginx `resolver` pattern
- `references/2-repo/env-and-config/frontend-env-isolation.md` — Vite vs Next env split
- `references/2-repo/deployment/production-readiness.md` — reverse-proxy hardening (TLS, limits, timeouts)
- `references/3-app/backend/serving.md` — the app-server workers nginx sits in front of
