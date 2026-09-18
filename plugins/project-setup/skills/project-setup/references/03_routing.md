# Setup — how the pieces connect, case by case

Every case below is the same system with a different number of pieces. Read the rules first. Then find your case. Each case says what changes in dev and in prod, and what does not.

## The rules that hold in every case

1. **Same-origin backend requests.** Production has one public origin. In development each frontend serves its own origin and proxies backend prefixes locally, so browser API calls remain relative. A shared origin across multiple development frontends is an explicit gateway configuration, not an automatic container.
2. **The edge is the `web` image.** One nginx that holds every static frontend and proxies everything else. Built by the single frontend's own `Dockerfile` (`example-single-web-app-vite/`) or by the group's (`example-multi-web-app/`); both build with context `./apps`. There is no second nginx service. `compose.base.yaml` ships wired to the group; the single shape's README holds the service block to swap in.
3. **`.env` defines every piece.** One `<PIECE>_HOST/_PORT/_PREFIX` block per proxied piece, `_PORT/_PREFIX` per static frontend, and the piece that owns `/` has no `_PREFIX`. The service binds `_PORT` and mounts `_PREFIX` from it; production nginx and framework development proxies read the same keys to route; a frontend reads its `_PREFIX` as `base` / `basePath` under the same key, no alias, no fallback. Definition and route are one key, so they cannot drift.
4. **Compose decides service names; `.env` decides the rest.** A service name is a literal in `compose.base.yaml` (`API_UPSTREAM: api:8000`). A host outside this compose comes from `.env` through `+env_override`.
5. **`ctl dev` runs apps on the host, engines in docker. `ctl up` runs everything in docker.** Same root .env file, same `config.yaml`, no edit between the two.
6. **Backends coordinate through the root .env file.** Shared secrets are one key in `.env` (`JWT_SIGNING_KEY`). A backend that calls another reads `<X>_URL` from its `config.yaml` as `${VAR}`; compose sets the literal in docker.

The routing table is `template/.env.template`. Read it there: one block per piece, the piece that owns `/` has no `_PREFIX`. Open a frontend's own port in development. Every path below that starts with `apps/` is a path inside `template/`.

## The pair: dev and prod

| | Dev — `ctl dev` | Prod — `ctl up` |
|---|---|---|
| Engines | the `dev` preset: a service subset of base plus `+expose_db`, loopback ports | defined directly in `compose.base.yaml`, no ports |
| Backends | on the host, `localhost:<port>`, reload | containers, service names |
| Static frontends | dev servers on their ports | built into the `web` image |
| Server frontend | `next dev` | `dashboard` container |
| The edge | each frontend's native proxy: Vite or framework rewrites | nginx in `web`, published by `+expose_web` on the `_PORT` of the piece that owns `/` (local), or by `+public` on 80/443. TLS and domains: a host proxy outside this repo. |
| Edge config | frontend `vite.config.ts` or `next.config.ts` | `apps/example-multi-web-app/nginx/nginx.conf.template`, copied into the image as `templates/default.conf.template` |

Framework proxies and production Nginx preserve the same public backend prefixes and WebSocket routes. Vite's proxy is development-only; it does not generate Nginx configuration. Keep both routing maps aligned when adding or changing a backend. Only production Nginx uses `envsubst` and its explicit variable allowlist.

## Case 1 — same server, one repo: frontend and backend together

The common case. Template: `apps/example-single-web-app-vite` + `apps/example-api-python`. The SPA owns its `Dockerfile` (build, then nginx serving `/` and proxying `/api`, `/engine`) and its `nginx.conf.template`. That image is the `web` service. No dev proxy: `vite.config.ts` proxies, so one frontend is one origin already.

| | Routing |
|---|---|
| Dev | `vite.config.ts` proxies `/api → 127.0.0.1:${API_PORT}`. `API_PORT` comes from the process env, which `ctl dev` filled from `.env`. The frontend calls `/api/…`. |
| Prod | `nginx.conf.template`: `location ${API_PREFIX}/ { proxy_pass http://${API_UPSTREAM}; }`. `API_UPSTREAM` is the literal `api:8000` in `compose.base.yaml`. |

Adding a backend: one `<X>_HOST/_PORT/_PREFIX` block in `.env.template`; one `location` in the production Nginx template; one `<X>_UPSTREAM` literal on `web` in `compose.base.yaml`, the name added to `NGINX_ENVSUBST_FILTER` and to `+env_override`; one proxy entry in `vite.config.ts`; one entry in the host-app declarations in `scripts/dev/_apps.sh`. Frontend code does not change.

## Case 2 — different server or different repo

The backend runs elsewhere: a managed service, another host, another repo. The browser still calls `/api`. The edge reaches out.

| | Routing |
|---|---|
| Dev | `.env`: `API_HOST=api.example.com`, `API_PORT=443`. The Vite proxy target becomes `https://${API_HOST}:${API_PORT}`, `changeOrigin: true`. Frontend code unchanged. |
| Prod | `ctl up +env_override`. The modifier re-points every upstream on `web` (`API_UPSTREAM: ${API_HOST}:${API_PORT}` and the rest), `ENGINE_URL` and `REDIS_URL` on `api`, `DATABASE_URL` and `NEO4J_URL` on `engine`, `API_HOST/_PORT` on `dashboard` — from `.env`. `ctl` refuses the modifier when a key in `MODIFIER_REQUIRES` (`_lib.sh`) is blank. |

CORS never appears: the edge talks to the remote backend, not the browser. The same holds in reverse, when the frontend is the remote piece: that repo's edge proxies to this backend's public host.

When only the database is elsewhere (managed Postgres), the same modifier re-points `DATABASE_URL`. Local database services are then not started: empty the `DATA_SVCS` default in `_lib.sh`, or export `DATA_SVCS=`, and remove the unused local engine and migration services from `base` (`08a_ctl_docker.md` § Worked example).

## Case 3 — several frontends

Production combines frontends under one origin: shared cookies, one login, links between `/` and `/app`. Template: `apps/example-multi-web-app/{landing,app,docs}` plus `apps/example-dashboard-nextjs`.

**Where they live.** Static frontends under one group folder, `apps/example-multi-web-app/<name>/`. Each owns its manifest, lock, `tsconfig.json`, README. No env file: its prefix arrives from `.env`. The group owns one `Dockerfile`, the `nginx/` templates and one `README.md`. A server frontend (Next.js SSR) is not in the group: it is `apps/example-dashboard-nextjs/`, its own image and service.

**Dev.** Open each selected frontend's own port. Vite proxies API and engine requests, including WebSocket upgrades; Next.js uses development rewrites, and Astro can use its Vite server options when it needs backend routes. Prefixes stay unchanged, so the browser still calls `/api/...` or `/engine/...`. No host-network Nginx container is started. Multiple ports are different origins: cross-frontend login/navigation tests that require one origin need an explicitly configured gateway in a chosen frontend dev server, or a production-shaped `ctl up` run. Vite does not automatically discover or aggregate the other frontends.

**Prod.** `apps/example-multi-web-app/Dockerfile`, context `./apps`:

1. One build stage per static frontend: `oven/bun:<version>`, `ARG` for that frontend's public keys, `bun install --frozen-lockfile`, `bun run build`.
2. Final stage `nginx:<version>`: `COPY` each output under its prefix in `/usr/share/nginx/html/`; `COPY nginx/nginx.conf.template` to `/etc/nginx/templates/default.conf.template`. nginx renders it at start from the container environment. Listens on 8080 as the `nginx` user (the Dockerfile chowns the cache and pid first). `+expose_web` publishes `${WEB_LANDING_PORT}:8080`, the port of the piece that owns `/` (`WEB_APP_PORT` in the single shape); `+public` publishes `${HTTP_PORT}:8080` and `${HTTPS_PORT}:8443`; `+expose` publishes every app port for debugging.

Build args are prefixes: compose passes `WEB_APP_PREFIX: ${WEB_APP_PREFIX}` and the like, interpolated from `.env`. No secret is ever a build arg.

**Adding a static frontend:** a folder under `apps/example-multi-web-app/`; one `<X>_PORT/_PREFIX` pair in `.env.template`; one build stage, one `ARG` and one `COPY --from` in the Dockerfile; one build arg in `compose.base.yaml`; one production Nginx `location` and prefix in its `NGINX_ENVSUBST_FILTER`; a native development proxy where needed; one entry in `scripts/dev/_apps.sh`.

## Case 4 — Next.js as a server

A frontend that renders on the server, runs its own routes, or must start fast. Template: `apps/example-dashboard-nextjs`.

| | Routing |
|---|---|
| Dev | `next.config.ts` rewrites `/api/* → http://127.0.0.1:${API_PORT}/api/*`. Server components fetch the same. |
| Prod | Container `dashboard` gets `API_HOST: api`, `API_PORT: 8000` from compose `environment:`. Server-side fetches use them. The browser side still calls `/api`, which the `web` edge routes. |

Server-only keys (no `NEXT_PUBLIC_` prefix) are allowed here and only here. Under `ctl dev` they come from `.env` through the process env. The app has no env file of its own. `output: "standalone"`, own Dockerfile, `basePath` = `DASHBOARD_PREFIX`.

## Case 5 — several backends

Template: `apps/example-api-python` (Python, identity, writes) and `apps/example-engine-rust` (Rust, data plane, reads). One backend per responsibility. A second backend needs a reason: a separate identity plane, a different runtime, an independent release cadence.

| Concern | Rule |
|---|---|
| Shared secret | One key in `.env`. Both read `JWT_SIGNING_KEY`. Keys not shared are separate: `ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`. |
| One backend calls another | The caller's `config.yaml` has `engine: { url: ${ENGINE_URL} }`. Dev: `.env` says `http://localhost:8080`. Docker: compose sets `ENGINE_URL: http://engine:8080`. The callee never knows. |
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
- Keep `Upgrade` / `Connection` headers on every WebSocket-capable production location, matching `ws: true` in Vite development proxies.
- `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` are set at the edge; a backend trusts them only from the edge.
- SPA fallback per prefix: `try_files $uri $uri/ ${WEB_APP_PREFIX}/index.html`. Without it deep links 404.
- `absolute_redirect off;` in every `server {}` that serves a directory. nginx answers a directory asked for without its slash (`/app?x=1`) with a 301 that adds the slash, and an absolute `Location` carries the port nginx listens on, 8080, not the port the browser used, so the browser leaves its origin. With it off the `Location` is `/app/?x=1`, resolved against the browser's own origin, query intact. A browser caches a 301: test with a fresh context. Both `nginx.conf.template` files carry it.
- Backend routes never at root: `/users` collides with SPA paths. API docs live under `${API_PREFIX}/docs`.

## Never

- A URL in a frontend bundle. `VITE_API_URL` per environment defeats the whole model.
- A second nginx service. The `web` image is the edge.
- A second static frontend beside a single one. Two static frontends means the group shape.
- A server frontend inside the group folder.
- A Dockerfile per static frontend.
- CORS middleware on a backend to reach a frontend of this product. If CORS is needed, the origin rule was broken.
- Serving a frontend from a backend (`StaticFiles`). nginx serves static.
- A backend host typed into compose that compose did not decide. That is `.env` and `+env_override`.
- A prefix typed into a framework config. It comes from `.env` as `base` / `basePath`.
