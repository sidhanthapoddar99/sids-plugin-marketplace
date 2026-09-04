# Setup — how the pieces connect, case by case

Every case below is the same system with a different number of pieces. Read the rules first. Then find your case. Each case says what changes in dev and in prod, and what does not.

## The rules that hold in every case

1. **One origin.** The browser sees one host. Every frontend and every backend sits behind it, separated by path prefix. Dev and prod route the same prefixes.
2. **The edge is the `web` image.** One nginx that holds every static frontend and proxies everything else. Built by the single frontend's own `Dockerfile` (`example-single-web-app-vite/`) or by the group's (`example-multi-web-app/`); both build with context `./apps`. There is no second nginx service. `compose.base.yaml` ships wired to the group; the single shape's README holds the service block to swap in.
3. **`.env.proxy` defines every piece.** One `<PIECE>_HOST/_PORT/_PREFIX` block per proxied piece, `_PORT/_PREFIX` per static frontend, and the piece that owns `/` has no `_PREFIX`. The service binds `_PORT` and mounts `_PREFIX` from it; nginx and the dev proxy read the same keys to route; a frontend reads its `_PREFIX` as `base` / `basePath` under the same key, no alias, no fallback. Definition and route are one key, so they cannot drift.
4. **Compose decides service names; `.env.proxy` decides the rest.** A service name is a literal in `compose.base.yaml` (`API_UPSTREAM: api:8000`). A host outside this compose comes from `.env.proxy` through `+env_override`.
5. **`ctl dev` runs apps on the host, engines in docker. `ctl up` runs everything in docker.** Same three env files, same `config.yaml`, no edit between the two.
6. **Backends coordinate through the root env files.** Shared secrets are one key in `.env.secrets` (`JWT_SIGNING_KEY`). A backend that calls another reads `<X>_URL` from its `config.yaml` as `${VAR}`; compose sets the literal in docker.

The routing table is `template/.env.proxy.template`. Read it there: one block per piece, the piece that owns `/` has no `_PREFIX`, and `DEV_PROXY_PORT` is the one origin in dev. Every path below that starts with `apps/` is a path inside `template/`.

## The pair: dev and prod

| | Dev — `ctl dev` | Prod — `ctl up` |
|---|---|---|
| Engines | `compose.db.yaml`, loopback ports | included by `compose.base.yaml` |
| Backends | on the host, `localhost:<port>`, reload | containers, service names |
| Static frontends | dev servers on their ports | built into the `web` image |
| Server frontend | `next dev` | `dashboard` container |
| The edge | Vite proxy (one frontend) or the dev proxy (several) | nginx in `web`, published by `+expose_web`. TLS and domains: a host proxy outside this repo. |
| Edge config | `apps/example-multi-web-app/nginx/nginx-dev.conf.template` + `nginx-dev-headers.conf` (the include every proxied location uses) | `apps/example-multi-web-app/nginx/nginx.conf.template`, copied into the image as `templates/default.conf.template` |

Both templates route the same prefixes. Prod serves the static ones from disk and proxies the rest to service names; dev proxies every prefix to `127.0.0.1:${PORT}`, websocket upgrade on all of them. Both are rendered by nginx's `envsubst`, limited to the names in `NGINX_ENVSUBST_FILTER` (set in compose) so nginx's own `$host` and `$request_uri` survive.

## Case 1 — same server, one repo: frontend and backend together

The common case. Template: `apps/example-single-web-app-vite` + `apps/example-api-python`. The SPA owns its `Dockerfile` (build, then nginx serving `/` and proxying `/api`, `/engine`) and its `nginx.conf.template`. That image is the `web` service. No dev proxy: `vite.config.ts` proxies, so one frontend is one origin already.

| | Routing |
|---|---|
| Dev | `vite.config.ts` proxies `/api → 127.0.0.1:${API_PORT}`. `API_PORT` comes from the process env, which `ctl dev` filled from `.env.proxy`. The frontend calls `/api/…`. |
| Prod | `nginx.conf.template`: `location ${API_PREFIX}/ { proxy_pass http://${API_UPSTREAM}; }`. `API_UPSTREAM` is the literal `api:8000` in `compose.base.yaml`. |

Adding a backend: one `<X>_HOST/_PORT/_PREFIX` block in `.env.proxy.template`; one `location` in both nginx templates; one `<X>_UPSTREAM` literal on `web` in `compose.base.yaml`, the name added to `NGINX_ENVSUBST_FILTER` and to `+env_override`; one proxy entry in `vite.config.ts`; one entry in the four `dev.sh` tables (`app_names`, `frontends`, `app_port`, `app_cmd`). Frontend code does not change.

## Case 2 — different server or different repo

The backend runs elsewhere: a managed service, another host, another repo. The browser still calls `/api`. The edge reaches out.

| | Routing |
|---|---|
| Dev | `.env.proxy`: `API_HOST=api.example.com`, `API_PORT=443`. The Vite proxy target becomes `https://${API_HOST}:${API_PORT}`, `changeOrigin: true`. Frontend code unchanged. |
| Prod | `ctl up +env_override`. The modifier re-points every upstream on `web` (`API_UPSTREAM: ${API_HOST}:${API_PORT}` and the rest), `ENGINE_URL` and `REDIS_URL` on `api`, `DATABASE_URL` and `NEO4J_URL` on `engine`, `API_HOST/_PORT` on `dashboard` — from `.env.proxy` and `.env.secrets`. `ctl` refuses the modifier when a key in `MODIFIER_REQUIRES` (`_lib.sh`) is blank. |

CORS never appears: the edge talks to the remote backend, not the browser. The same holds in reverse, when the frontend is the remote piece: that repo's edge proxies to this backend's public host.

When only the database is elsewhere (managed Postgres), the same modifier re-points `DATABASE_URL`. `compose.db.yaml` is then not started: empty the `DATA_SVCS` default in `_lib.sh`, or export `DATA_SVCS=`. `ctl up` then skips `migrate`, and `ctl check` skips compose validation.

## Case 3 — several frontends

Two or more frontends must share one origin: shared cookies, one login, links between `/` and `/app`. Template: `apps/example-multi-web-app/{landing,app,docs}` plus `apps/example-dashboard-nextjs`.

**Where they live.** Static frontends under one group folder, `apps/example-multi-web-app/<name>/`. Each owns its manifest, lock, `tsconfig.json`, README. No env file: its prefix arrives from `.env.proxy`. The group owns one `Dockerfile`, the `nginx/` templates and one `README.md`. A server frontend (Next.js SSR) is not in the group: it is `apps/example-dashboard-nextjs/`, its own image and service.

**Dev.** `ctl dev --proxy`, automatic when two or more frontends are selected. `docker/compose.dev.yaml` runs one nginx on the host network with `nginx-dev.conf.template`: `/ → 127.0.0.1:${WEB_LANDING_PORT}`, `/app → :${WEB_APP_PORT}`, `/docs → :${WEB_DOCS_PORT}`, `/dashboard → :${DASHBOARD_PORT}`, `/api → :${API_PORT}`, `/engine → :${ENGINE_PORT}`. Websocket upgrade on every location, so HMR works through it. Open `http://localhost:${DEV_PROXY_PORT}`. The Vite proxy block stays for single-frontend dev; under the dev proxy it is never hit.

**Prod.** `apps/example-multi-web-app/Dockerfile`, context `./apps`:

1. One build stage per static frontend: `oven/bun:<version>`, `ARG` for that frontend's public keys, `bun install --frozen-lockfile`, `bun run build`.
2. Final stage `nginx:<version>`: `COPY` each output under its prefix in `/usr/share/nginx/html/`; `COPY nginx/nginx.conf.template` to `/etc/nginx/templates/default.conf.template`. nginx renders it at start from the container environment. Listens on 8080 as the `nginx` user (the Dockerfile chowns the cache and pid first). `+expose_web` publishes `${HTTP_PORT}:8080` and `${HTTPS_PORT}:8443`; `+expose` publishes every app port for debugging.

Build args are prefixes: compose passes `VITE_BASE_PATH: ${WEB_APP_PREFIX}` and the like, interpolated from `.env.proxy`. No secret is ever a build arg.

**Adding a static frontend:** a folder under `apps/example-multi-web-app/`; one `<X>_PORT/_PREFIX` pair in `.env.proxy.template`; one build stage, one `ARG` and one `COPY --from` in the Dockerfile; one build arg in `compose.base.yaml`; one `location` in both templates and the prefix name in both `NGINX_ENVSUBST_FILTER` lists; one entry in the four `dev.sh` tables.

## Case 4 — Next.js as a server

A frontend that renders on the server, runs its own routes, or must start fast. Template: `apps/example-dashboard-nextjs`.

| | Routing |
|---|---|
| Dev | `next.config.ts` rewrites `/api/* → http://127.0.0.1:${API_PORT}/api/*`. Server components fetch the same. |
| Prod | Container `dashboard` gets `API_HOST: api`, `API_PORT: 8000` from compose `environment:`. Server-side fetches use them. The browser side still calls `/api`, which the `web` edge routes. |

Server-only keys (no `NEXT_PUBLIC_` prefix) are allowed here and only here. Under `ctl dev` they come from `.env.secrets` through the process env. The app has no env file of its own. `output: "standalone"`, own Dockerfile, `basePath` = `DASHBOARD_PREFIX`.

## Case 5 — several backends

Template: `apps/example-api-python` (Python, identity, writes) and `apps/example-engine-rust` (Rust, data plane, reads). One backend per responsibility. A second backend needs a reason: a separate identity plane, a different runtime, an independent release cadence.

| Concern | Rule |
|---|---|
| Shared secret | One key in `.env.secrets`. Both read `JWT_SIGNING_KEY`. Keys not shared are separate: `ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`. |
| One backend calls another | The caller's `config.yaml` has `engine: { url: ${ENGINE_URL} }`. Dev: `.env.proxy` says `http://localhost:8080`. Docker: compose sets `ENGINE_URL: http://engine:8080`. The callee never knows. |
| Shared database | One owner of the schema: `apps/database/`. Migrations are hand-written there (see `06_backend.md`). Both backends read; one writes. No table belongs to two services. |
| Routing | Each backend has its own prefix and `location`. The edge does not know which language is behind it. |
| Identity planes | Admin and user APIs are two backends when their auth differs (`api-admin`, `api-platform`), one when it does not. |

Core vs BFF: a "backend for frontend" that only reshapes a core API is not a second backend. It is a router module in the one backend, or the Next.js server of case 4.

## Case 6 — one static frontend, no backend

A landing page, a docs site. The single shape (`example-single-web-app-vite/`, or the same with Next.js export or Astro) with the proxied locations deleted from its `nginx.conf.template`. `DATA_SVCS=()`. `compose.base.yaml` keeps only `web`. `ctl dev` runs one dev server.

## Case 7 — a second origin

Two cases earn a second origin. Everything else is a prefix.

| Case | Shape |
|---|---|
| A separate identity plane | An admin surface with its own login and its own backend (`api-admin`) lives on its own host (`admin.<domain>`). It is a second `server {}` block in the same `nginx.conf.template`, keyed on `server_name`, with its own upstreams — still one `web` image, one compose. Cookies and sessions never cross. |
| A public SDK or embeddable widget | Consumed from third-party sites. That is a package under `apps/packages/`, published, with its own CORS story. Not a frontend of this product. |

## nginx rules that bite

- Longest prefix wins, so order `location` blocks from most specific to least; `/live/ws` before `/ws`, and one websocket prefix per plane so upgrades never clash.
- A variable in `proxy_pass` (`http://${API_UPSTREAM}`) does not append the matched URI; the template passes the path explicitly.
- `Upgrade` / `Connection` headers on every websocket-capable location in prod, not only in the dev proxy.
- `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` are set at the edge; a backend trusts them only from the edge.
- SPA fallback per prefix: `try_files $uri $uri/ ${WEB_APP_PREFIX}/index.html`. Without it deep links 404.
- Backend routes never at root: `/users` collides with SPA paths. API docs live under `${API_PREFIX}/docs`.

## Never

- A URL in a frontend bundle. `VITE_API_URL` per environment defeats the whole model.
- A second nginx service. The `web` image is the edge.
- A second static frontend beside a single one. Two static frontends means the group shape.
- A server frontend inside the group folder.
- A Dockerfile per static frontend.
- CORS middleware on a backend to reach a frontend of this product. If CORS is needed, the origin rule was broken.
- Serving a frontend from a backend (`StaticFiles`). nginx serves static.
- A backend host typed into compose that compose did not decide. That is `.env.proxy` and `+env_override`.
- A prefix typed into a framework config. It comes from `.env.proxy` as `base` / `basePath`.
