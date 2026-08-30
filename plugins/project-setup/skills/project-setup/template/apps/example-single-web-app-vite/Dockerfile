# The web image for a single-frontend product: build the bundle, serve it with nginx, proxy the backends.
# Build context is ./apps (needs packages/): compose sets `context: ./apps, dockerfile: example-single-web-app-vite/Dockerfile`.
# The only build arg is the prefix, interpolated by compose from .env.proxy. No secret is ever a build arg.

# ---- build: Vite → dist/ ----
FROM oven/bun:<version> AS build
WORKDIR /src
COPY packages ./packages
COPY example-single-web-app-vite ./example-single-web-app-vite
# the single shape owns /; no prefix arg
RUN cd example-single-web-app-vite && bun install --frozen-lockfile && bun run build

# ---- edge: nginx serves the bundle at / and proxies api / engine ----
FROM nginx:<version>
# prefixes and upstreams arrive at runtime as env; the nginx image renders *.template with envsubst
COPY example-single-web-app-vite/nginx/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/example-single-web-app-vite/dist/ /usr/share/nginx/html/
# non-root: the official image ships the `nginx` user; listen on an unprivileged port
RUN chown -R nginx:nginx /var/cache/nginx /etc/nginx/conf.d && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx
EXPOSE 8080
