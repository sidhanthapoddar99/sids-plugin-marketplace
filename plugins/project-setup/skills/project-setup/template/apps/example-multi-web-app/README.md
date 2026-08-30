# web — the static frontend group

One image, one service, the single edge. Every frontend that builds to static files lives here as
`apps/example-multi-web-app/<name>/`. The shared `Dockerfile` builds each one and copies the output into one
`nginx:<version>` image. That image is the production edge: it serves the static frontends and
proxies `/api`, `/engine` and `/dashboard` to their containers.

| Name | Kind | Prefix (`.env.proxy`) | Dev port (`.env.proxy`) |
|---|---|---|---|
| `landing/` | Next.js `output: "export"` — SEO pages | owns `/` (no prefix key) | `WEB_LANDING_PORT=3001` |
| `app/` | Vite SPA — the product UI | `WEB_APP_PREFIX=/app` | `WEB_APP_PORT=5173` |
| `docs/` | Astro — documentation | `WEB_DOCS_PREFIX=/docs` | `WEB_DOCS_PORT=4321` |

Not in this group: `apps/example-dashboard-nextjs/` (Next.js SSR). It needs a Node server, so it is its own image and
the edge proxies to it under `DASHBOARD_PREFIX`.

## The prefix rule

One origin. Every frontend owns one path prefix and nothing else. The prefix is set once in
`.env.proxy` and read by three places: the frontend's own build config (`base` / `basePath`, arriving as a
compose build arg — there is no per-frontend `.env`),
`nginx/nginx.conf.template` (prod, copied into the image) and `nginx/nginx-dev.conf.template` (the dev proxy, mounted by `docker/compose.dev.yaml`). Both live here because this group owns the edge.

## Each frontend still owns

`package.json` + lock, `tsconfig.json`, `README.md`. Only the Dockerfile is shared. No `.env` here: the
prefix is a build arg from `.env.proxy`; a display name is a literal in the framework config.
No `package.json` directly in `apps/example-multi-web-app/` — `ctl check` fails it.

## Add a frontend

1. New folder `apps/example-multi-web-app/<name>/` with its own manifest.
2. One build stage in `apps/example-multi-web-app/Dockerfile` and one `COPY --from` line into the nginx stage.
3. One `location` block in both `nginx/nginx.conf.template` and `nginx/nginx-dev.conf.template`.
4. One `WEB_<NAME>_PREFIX` and `WEB_<NAME>_PORT` in `.env.proxy.template`, one build arg in `compose.base.yaml`, plus the port in `ctl dev`'s app table.

## Run

`ctl dev app` — one frontend, its own dev server, the Vite/Next proxy handles `/api`.
`ctl dev app landing` — two or more: `ctl` also starts the nginx dev proxy (`docker/compose.dev.yaml`) so
every frontend is reachable on one origin at `http://localhost:${DEV_PROXY_PORT}`.
