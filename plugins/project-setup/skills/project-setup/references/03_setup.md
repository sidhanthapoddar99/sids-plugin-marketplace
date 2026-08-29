# Setup — how the pieces connect, case by case

Every case below is the same system with a different number of pieces. Read the rules first. Then find your case. Each case says what changes in dev and in prod, and what does not.

## The rules that hold in every case

1. **One origin.** The browser sees one host. Every frontend and every backend sits behind it, separated by path prefix. Dev and prod route the same prefixes.
2. **The edge is the `web` image.** One nginx that holds every static frontend and proxies everything else. Built by the single frontend's own `Dockerfile` (`example-single-web-app-vite/`) or by the group's (`example-multi-web-app/`). There is no second nginx service.
3. **Prefixes and ports live in the root `.env`.** One prefix and one dev port per piece. nginx reads them by `envsubst`. The framework reads its own prefix as `base` / `basePath`.
4. **Compose decides service names; `.env` decides the rest.** A service name is a literal in `compose.base.yaml` (`API_UPSTREAM: api:8000`). A host outside this compose comes from `.env` through `+env_override`.
5. **`ctl dev` runs apps on the host, engines in docker. `ctl up` runs everything in docker.** Same `.env`, same `config.yaml`, no edit between the two.
6. **Backends coordinate through the root `.env`.** Shared secrets are one key (`JWT_SIGNING_KEY`). A backend that calls another reads `<X>_URL` from its `config.yaml` as `${VAR}`; compose sets the literal in docker.

The routing table, from `template/.env.example`:

```
WEB_LANDING_PREFIX=/          WEB_LANDING_PORT=3001   apps/example-multi-web-app/landing   Next.js export
WEB_APP_PREFIX=/app           WEB_APP_PORT=5173       apps/example-multi-web-app/app       Vite SPA
WEB_DOCS_PREFIX=/docs         WEB_DOCS_PORT=4321      apps/example-multi-web-app/docs      Astro
DASHBOARD_PREFIX=/dashboard   DASHBOARD_PORT=3000     apps/example-dashboard-nextjs        Next.js server
API_PREFIX=/api               API_PORT=8000           apps/example-api-python              FastAPI
ENGINE_PREFIX=/engine         ENGINE_PORT=8080        apps/example-engine-rust             Axum
DEV_PROXY_PORT=3080                                   docker/compose.dev.yaml              the one origin in dev
```

## The pair: dev and prod

| | Dev — `ctl dev` | Prod — `ctl up` |
|---|---|---|
| Engines | `compose.db.yaml`, loopback ports | included by `compose.base.yaml` |
| Backends | on the host, `localhost:<port>`, reload | containers, service names |
| Static frontends | dev servers on their ports | built into the `web` image |
| Server frontend | `next dev` | `dashboard` container |
| The edge | Vite proxy (one frontend) or the dev proxy (several) | nginx in `web`, published by `+expose_web`. TLS and domains: a host proxy outside this repo. |
| Edge config | `apps/infra/nginx-dev/dev.conf.template` | `apps/infra/nginx/prod.conf.template` |

Both templates carry the same `location` blocks. Only the upstream differs: `127.0.0.1:${PORT}` in dev, a service name in prod.

## Case 1 — same server, one repo: frontend and backend together

The common case. Template: `apps/example-single-web-app-vite` + `apps/example-api-python`. The SPA owns its `Dockerfile` (build, then nginx serving `/` and proxying `/api`, `/engine`) and its `nginx.conf.template`. That image is the `web` service. No dev proxy: `vite.config.ts` proxies, so one frontend is one origin already.

| | Routing |
|---|---|
| Dev | `vite.config.ts` proxies `/api → 127.0.0.1:${API_PORT}`. `API_PORT` comes from the process env, which `ctl dev` filled from root `.env`. The frontend calls `/api/…`. |
| Prod | `prod.conf.template`: `location ${API_PREFIX}/ { proxy_pass http://${API_UPSTREAM}; }`. `API_UPSTREAM` is the literal `api:8000` in `compose.base.yaml`. |

Adding a backend: one proxy entry in `vite.config.ts`, one `location` in both nginx templates, one `<X>_UPSTREAM` literal in compose, one prefix and port in `.env.example`. Frontend code does not change.

## Case 2 — different server or different repo

The backend runs elsewhere: a managed service, another host, another repo. The browser still calls `/api`. The edge reaches out.

| | Routing |
|---|---|
| Dev | Root `.env`: `API_HOST=api.example.com`, `API_PORT=443`. The Vite proxy target becomes `https://${API_HOST}:${API_PORT}`, `changeOrigin: true`. Frontend code unchanged. |
| Prod | `ctl up +env_override`. The modifier sets `API_UPSTREAM: ${API_HOST}:${API_PORT}` on `web` and `ENGINE_URL: ${ENGINE_URL}` on `api`, from root `.env`. `ctl` refuses the modifier when a mapped key is blank. |

CORS never appears: the edge talks to the remote backend, not the browser. The same holds in reverse, when the frontend is the remote piece: that repo's edge proxies to this backend's public host.

When only the database is elsewhere (managed Postgres), the same modifier re-points `DATABASE_URL`. `compose.db.yaml` is then not started: `DATA_SVCS=()` in `_lib.sh`.

## Case 3 — several frontends

Two or more frontends must share one origin: shared cookies, one login, links between `/` and `/app`. Template: `apps/example-multi-web-app/{landing,app,docs}` plus `apps/example-dashboard-nextjs`.

**Where they live.** Static frontends under one group folder, `apps/example-multi-web-app/<name>/`. Each owns its manifest, lock, `.env.example`, `tsconfig.json`, README. The group owns one `Dockerfile` and one `README.md`. A server frontend (Next.js SSR) is not in the group: it is `apps/example-dashboard-nextjs/`, its own image and service.

**Dev.** `ctl dev --proxy`, automatic when two or more frontends are selected. `docker/compose.dev.yaml` runs one nginx on the host network with `dev.conf.template`: `/ → 127.0.0.1:${WEB_LANDING_PORT}`, `/app → :${WEB_APP_PORT}`, `/dashboard → :${DASHBOARD_PORT}`, `/api → :${API_PORT}`. Websocket upgrade on every location, so HMR works through it. Open `http://localhost:${DEV_PROXY_PORT}`. The Vite proxy block stays for single-frontend dev; under the dev proxy it is never hit.

**Prod.** `apps/example-multi-web-app/Dockerfile`, context `./apps`:

1. One build stage per static frontend: `oven/bun:<version>`, `ARG` for that frontend's public keys, `bun install --frozen-lockfile`, `bun run build`.
2. Final stage `nginx:<version>`: `COPY` each output under its prefix in `/usr/share/nginx/html/`; `COPY prod.conf.template` to `/etc/nginx/templates/`. nginx renders it at start from the container environment. Listens on 8080, unprivileged. `+expose_web` publishes `${HTTP_PORT}:8080`.

`ctl build` forwards each `apps/example-multi-web-app/<name>/.env` as build args. Compose lists the arg names, never the values.

**Adding a static frontend:** a folder under `apps/example-multi-web-app/`, one build stage and one `COPY --from` in the Dockerfile, one `location` in both templates, one prefix and port in `.env.example`, one line in `app_names` in `scripts/dev/dev.sh`.

## Case 4 — Next.js as a server

A frontend that renders on the server, runs its own routes, or must start fast. Template: `apps/example-dashboard-nextjs`.

| | Routing |
|---|---|
| Dev | `next.config.ts` rewrites `/api/* → http://127.0.0.1:${API_PORT}/api/*`. Server components fetch the same. |
| Prod | Container `dashboard` gets `API_HOST: api`, `API_PORT: 8000` from compose `environment:`. Server-side fetches use them. The browser side still calls `/api`, which the `web` edge routes. |

Server-only keys (no `NEXT_PUBLIC_` prefix) are allowed here and only here. Under `ctl dev` they come from root `.env` through the process env, never from `apps/example-dashboard-nextjs/.env`. `output: "standalone"`, own Dockerfile, `basePath` = `DASHBOARD_PREFIX`.

## Case 5 — several backends

Template: `apps/example-api-python` (Python, identity, writes) and `apps/example-engine-rust` (Rust, data plane, reads). One backend per responsibility. A second backend needs a reason: a separate identity plane, a different runtime, an independent release cadence.

| Concern | Rule |
|---|---|
| Shared secret | One key in root `.env`. Both read `JWT_SIGNING_KEY`. Keys not shared are separate: `ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`. |
| One backend calls another | The caller's `config.yaml` has `engine: { url: ${ENGINE_URL} }`. Dev: `.env` says `http://localhost:8080`. Docker: compose sets `ENGINE_URL: http://engine:8080`. The callee never knows. |
| Shared database | One owner of the schema: `apps/database/`. Migrations are hand-written there (see `04_stack.md`). Both backends read; one writes. No table belongs to two services. |
| Routing | Each backend has its own prefix and `location`. The edge does not know which language is behind it. |
| Identity planes | Admin and user APIs are two backends when their auth differs (`api-admin`, `api-platform`), one when it does not. |

Core vs BFF: a "backend for frontend" that only reshapes a core API is not a second backend. It is a router module in the one backend, or the Next.js server of case 4.

## Case 6 — one static frontend, no backend

A landing page, a docs site. The single shape (`example-single-web-app-vite/`, or the same with Next.js export or Astro) with the proxied locations deleted from its `nginx.conf.template`. `DATA_SVCS=()`. `compose.base.yaml` keeps only `web`. `ctl dev` runs one dev server.

## Case 7 — multiple origins

Only for a public SDK or an embeddable widget consumed from third-party sites. That is a package under `apps/packages/`, published, with its own CORS story. It is not a frontend of this product and changes nothing above.

## Never

- A URL in a frontend bundle. `VITE_API_URL` per environment defeats the whole model.
- A second nginx service. The `web` image is the edge.
- A second static frontend beside a single one. Two static frontends means the group shape.
- A server frontend inside the group folder.
- A Dockerfile per static frontend.
- CORS middleware on a backend to reach a frontend of this product. If CORS is needed, the origin rule was broken.
- Serving a frontend from a backend (`StaticFiles`). nginx serves static.
- A backend host typed into compose that compose did not decide. That is `.env` and `+env_override`.
- Prefixes that differ between `.env` and the framework config. `ctl check` compares them.
