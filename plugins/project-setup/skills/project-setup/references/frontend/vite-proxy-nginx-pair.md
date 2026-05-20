# Vite proxy in dev → nginx in prod

The frontend never needs to know which environment it's in. In dev, Vite proxies `/api/*` to the backend. In prod, nginx routes `/api/*` to the backend container. Same URL contract.

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

## Frontend Dockerfile (multi-stage)

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

## Anti-patterns

- Hardcoding `http://localhost:8000` in frontend code — breaks in prod
- Different `VITE_API_BASE_URL` per environment — defeats the proxy
- Forgetting WebSocket upgrade headers in nginx — sync silently breaks
- Proxying `/api` to a host different from where nginx serves — CORS reappears
- Serving the frontend from the backend (e.g. FastAPI + StaticFiles) — slower in prod, mixes concerns; use nginx
