# example-single-web-app-vite — one Vite SPA, its own image

The shape for a product with ONE static frontend. Compare `example-multi-web-app/`, the shape for several.

- Served at `/`. Static bundle, no server. Calls `/api` and `/engine` on its own origin.
- Owns its `Dockerfile`: build the bundle, end in nginx with `nginx/nginx.conf.template`, proxy the backends.
  This image is the `web` service and the edge — the same role `example-multi-web-app/Dockerfile` plays.
- Owns `vite.config.ts` with the dev proxy, so `ctl dev` needs no nginx dev proxy: one frontend, one origin already.

Run from here: `ctl dev single` (exports `.env.secrets`, `.env.data`, `.env.proxy`, then `bun dev`).
No `.env` here. It owns `/`, so no prefix key; ports and proxy targets come from `.env.proxy`. Test: `bun test`. The browser suite (`e2e/`) is an add-on.

`src/` follows the frontend shape in the `project-setup` skill, `05_frontend.md` § The folder shape: `routes/` (TanStack Router file routing), `layout/`, `modules/`, `components/`, `lib/`, `styles/`. Each file's header comment says what it holds and what it may import.

## Using this shape instead of the group

`compose.base.yaml` ships with the group. To switch:

```yaml
  web:
    image: ${REGISTRY}/web:${TAG}
    build:
      context: ./apps
      dockerfile: example-single-web-app-vite/Dockerfile
      args:
    environment:
      API_PREFIX: ${API_PREFIX}
      ENGINE_PREFIX: ${ENGINE_PREFIX}
      API_UPSTREAM: api:8000
      ENGINE_UPSTREAM: engine:8080
      NGINX_ENVSUBST_FILTER: ^(API_PREFIX|ENGINE_PREFIX|API_UPSTREAM|ENGINE_UPSTREAM)$
    depends_on: [api, engine]
```

Then delete `example-multi-web-app/`, `docker/compose.dev.yaml`, and the `WEB_LANDING_*`, `WEB_DOCS_*`, `DASHBOARD_*`, `DEV_PROXY_PORT` keys in `.env.proxy.template`. Keep `WEB_APP_PORT`; set `WEB_APP_PREFIX=/`. In `compose.m.expose_web.yaml` and `compose.m.expose.yaml`, publish `web` on `${WEB_APP_PORT}` instead of `${WEB_LANDING_PORT}`: this app owns `/`, so the edge takes its port, and `http://localhost:${WEB_APP_PORT}` is the product under `ctl dev` and under `ctl up` alike.
