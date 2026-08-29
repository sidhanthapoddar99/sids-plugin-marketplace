# example-single-web-app-vite — one Vite SPA, its own image

The shape for a product with ONE static frontend. Compare `example-multi-web-app/`, the shape for several.

- Served at `/`. Static bundle, no server. Calls `/api` and `/engine` on its own origin.
- Owns its `Dockerfile`: build the bundle, end in nginx with `nginx.conf.template`, proxy the backends.
  This image is the `web` service and the edge — the same role `example-multi-web-app/Dockerfile` plays.
- Owns `vite.config.ts` with the dev proxy, so `ctl dev` needs no nginx dev proxy: one frontend, one origin already.

Run from here: `bun install && bun dev` (export the root `.env` first, or use `ctl dev single`).
Env: `.env`, public `VITE_*` only. Test: `bun test`, e2e in `e2e/`.

## Using this shape instead of the group

`compose.base.yaml` ships with the group. To switch:

```yaml
  web:
    image: ${REGISTRY}/web:${TAG}
    build:
      context: ./apps
      dockerfile: example-single-web-app-vite/Dockerfile
      args: [VITE_APP_NAME]
    environment:
      API_PREFIX: ${API_PREFIX}
      ENGINE_PREFIX: ${ENGINE_PREFIX}
      API_UPSTREAM: api:8000
      ENGINE_UPSTREAM: engine:8080
      NGINX_ENVSUBST_FILTER: ^(API_PREFIX|ENGINE_PREFIX|API_UPSTREAM|ENGINE_UPSTREAM)$
    depends_on: [api, engine]
```

Then delete `example-multi-web-app/`, `apps/infra/nginx-dev/`, `docker/compose.dev.yaml`, and the `WEB_LANDING_*`, `WEB_DOCS_*`, `DASHBOARD_*`, `DEV_PROXY_PORT` keys. Keep `WEB_APP_PORT`; set `WEB_APP_PREFIX=/`.
