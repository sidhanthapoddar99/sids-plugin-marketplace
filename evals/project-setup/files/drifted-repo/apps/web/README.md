# web — one Vite SPA, its own image

The shape for a product with ONE static frontend. Compare `example-multi-web-app/`, the shape for several.

- Served at `/`. Static bundle, no server. Calls `/api` and `/engine` on its own origin.
- Owns its `Dockerfile`: build the bundle, end in nginx with `nginx/nginx.conf.template`, proxy the backends.
  This image is the `web` service and the edge — the same role `example-multi-web-app/Dockerfile` plays.
- Owns `vite.config.ts` with the dev proxy, so `ctl dev` needs no nginx dev proxy: one frontend, one origin already.

Run from here: `ctl dev single` (exports `.env.secrets`, `.env.data`, `.env.proxy`, then `bun dev`).
No `.env` here. It owns `/`, so no prefix key; ports and proxy targets come from `.env.proxy`. Test: `bun test`, e2e in `e2e/`.

## Using this shape instead of the group

`compose.base.yaml` ships with the group. To switch:

```yaml
  web:
    image: ${REGISTRY}/web:${TAG}
    build:
      context: ./apps
      dockerfile: web/Dockerfile
      args:
    environment:
      API_PREFIX: ${API_PREFIX}
      ENGINE_PREFIX: ${ENGINE_PREFIX}
      API_UPSTREAM: api:8000
      ENGINE_UPSTREAM: engine:8080
      NGINX_ENVSUBST_FILTER: ^(API_PREFIX|ENGINE_PREFIX|API_UPSTREAM|ENGINE_UPSTREAM)$
    depends_on: [api, engine]
```

