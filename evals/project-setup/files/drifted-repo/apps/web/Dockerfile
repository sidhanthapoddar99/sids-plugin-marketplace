# The web image for a single-frontend product: build the bundle, serve it with nginx, proxy the backends.
# Build context is ./apps (needs packages/): compose sets `context: ./apps, dockerfile: web/Dockerfile`.
# The only build arg is the prefix, interpolated by compose from .env.proxy. No secret is ever a build arg.

# ---- build: Vite → dist/ ----
FROM oven/bun:3.13 AS build
WORKDIR /src
COPY packages ./packages
COPY web ./web
# the single shape owns /; no prefix arg
RUN cd web && bun install --frozen-lockfile && bun run build

# ---- edge: nginx serves the bundle at / and proxies api ----
FROM nginx:3.13
# prefixes and upstreams arrive at runtime as env; the nginx image renders *.template with envsubst
COPY web/nginx/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/web/dist/ /usr/share/nginx/html/
# non-root: the official image ships the `nginx` user; listen on an unprivileged port
RUN chown -R nginx:nginx /var/cache/nginx /etc/nginx/conf.d && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx
EXPOSE 8080
