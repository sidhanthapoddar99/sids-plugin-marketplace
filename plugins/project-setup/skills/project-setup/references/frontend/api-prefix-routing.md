# `/api/*` prefix routing

Every backend route this frontend calls lives under `/api/*`. This single rule makes the Vite-proxy-and-nginx-routing pattern (`vite-proxy-nginx-pair.md`) work.

## The rule

- Backend mounts routes under `/api/<endpoint>` (e.g. `/api/users`, `/api/sessions`)
- Frontend code calls `/api/<endpoint>` (no host, just the path)
- Vite proxies `/api/*` in dev, nginx routes `/api/*` in prod
- All other paths (`/`, `/login`, `/dashboard`) are the SPA

## Backend implementation

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

## Frontend implementation

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

`VITE_API_BASE_URL=/api` in dev and prod — same value. Only the proxy / nginx routing differs underneath.

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

## When the rule breaks

- **Reverse proxy headers** — backend must read `X-Forwarded-*` to know the real origin (set by nginx/traefik)
- **WebSockets** — `/ws/*` is a separate prefix; nginx needs the Upgrade headers
- **CDN-fronted assets** — static asset URLs may live on a different host (CDN), but that's the SPA's problem, not the API routing

## Anti-patterns

- Backend routes at root (`/users`, `/sessions`) — collides with SPA paths
- Different prefixes per endpoint (`/api/v1/...`, `/admin/...`) — pick one rule
- Hard-coding the full backend URL in frontend code — breaks the proxy pattern
- Per-environment `VITE_API_BASE_URL` — defeats CORS-free dev
- Mounting docs (Swagger / `/docs`) at root — under `/api/docs` so it follows the same routing
