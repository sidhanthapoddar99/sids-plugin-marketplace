# web — the static frontend group

One image, one service, the single edge. Every frontend that builds to static files lives here as
`apps/example-multi-web-app/<name>/`. The shared `Dockerfile` builds each one and copies the output into one
`nginx:<version>` image. That image is the production edge: it serves the static frontends and
proxies `/api`, `/engine` and `/dashboard` to their containers.

| Name | Kind | Prefix (`.env`) | Dev port (`.env`) |
|---|---|---|---|
| `landing/` | Next.js `output: "export"` — SEO pages | owns `/` (no prefix key) | `WEB_LANDING_PORT=3001` |
| `app/` | Vite SPA — the product UI | `WEB_APP_PREFIX=/app` | `WEB_APP_PORT=5173` |
| `docs/` | Astro — documentation | `WEB_DOCS_PREFIX=/docs` | `WEB_DOCS_PORT=4321` |

Not in this group: `apps/example-dashboard-nextjs/` (Next.js SSR). It needs a Node server, so it is its own image and
the edge proxies to it under `DASHBOARD_PREFIX`.

## The prefix rule

Production uses one origin. Each frontend's prefix is set once in `.env` and read by its own build config (`base` / `basePath`, arriving as a Compose build argument) and `nginx/nginx.conf.template`, the production edge. There is no frontend-local env file. Development routing belongs to each frontend's Vite proxy or framework rewrites; these preserve the same backend prefixes on the frontend's own port.

## Each frontend still owns

`package.json` + lock, `tsconfig.json`, `README.md`. Only the Dockerfile is shared. No `.env` here: the
prefix is a build arg from `.env`; a display name is a literal in the framework config.
No `package.json` directly in `apps/example-multi-web-app/` — `ctl check` fails it.

## Add a frontend

1. New folder `apps/example-multi-web-app/<name>/` with its own manifest.
2. One build stage in `apps/example-multi-web-app/Dockerfile` and one `COPY --from` line into the nginx stage.
3. One production `location` in `nginx/nginx.conf.template`, with matching backend proxy rules in the frontend's development config.
4. One `WEB_<NAME>_PREFIX` and `WEB_<NAME>_PORT` in `.env.template`, one build arg in `compose.base.yaml`, plus the port in `ctl dev`'s app table.

## Run

`ctl dev app` — one frontend, its own dev server, the Vite/Next proxy handles `/api`.
`ctl dev app landing` starts both frontend servers on their own ports. Vite handles the app's backend HTTP and WebSocket routes; no extra Nginx container or host networking is needed. Cross-frontend flows requiring a shared origin need an explicit frontend gateway or a production-shaped `ctl up` run.
