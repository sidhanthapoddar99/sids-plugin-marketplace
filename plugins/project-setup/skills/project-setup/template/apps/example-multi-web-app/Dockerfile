# The web image: every static frontend built, one nginx serving them all and proxying the rest.
# Build context is ./apps (needs packages/): compose sets `context: ./apps, dockerfile: example-multi-web-app/Dockerfile`.
# One build stage per frontend. The only build args are the prefixes, interpolated by compose from .env.proxy.
# No secret is ever a build arg — an ARG stays in the image history.

# ---- landing: Next.js static export → out/ ----
FROM oven/bun:<version> AS landing
WORKDIR /src
COPY packages ./packages
COPY example-multi-web-app/landing ./example-multi-web-app/landing
ARG NEXT_PUBLIC_BASE_PATH=
ENV NEXT_PUBLIC_BASE_PATH=${NEXT_PUBLIC_BASE_PATH}
RUN cd example-multi-web-app/landing && bun install --frozen-lockfile && bun run build

# ---- app: Vite SPA → dist/ ----
FROM oven/bun:<version> AS app
WORKDIR /src
COPY packages ./packages
COPY example-multi-web-app/app ./example-multi-web-app/app
ARG VITE_BASE_PATH=/app
ENV VITE_BASE_PATH=${VITE_BASE_PATH}
RUN cd example-multi-web-app/app && bun install --frozen-lockfile && bun run build

# ---- docs: Astro → dist/ ----
FROM oven/bun:<version> AS docs
WORKDIR /src
COPY packages ./packages
COPY example-multi-web-app/docs ./example-multi-web-app/docs
ARG PUBLIC_BASE_PATH=/docs
ENV PUBLIC_BASE_PATH=${PUBLIC_BASE_PATH}
RUN cd example-multi-web-app/docs && bun install --frozen-lockfile && bun run build

# ---- edge: nginx serves the three builds and proxies api / engine / dashboard ----
FROM nginx:<version>
# prefixes and upstreams arrive at runtime as env; the nginx image renders *.template with envsubst
COPY example-multi-web-app/nginx/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=landing /src/example-multi-web-app/landing/out/  /usr/share/nginx/html/
COPY --from=app     /src/example-multi-web-app/app/dist/     /usr/share/nginx/html/app/
COPY --from=docs    /src/example-multi-web-app/docs/dist/    /usr/share/nginx/html/docs/
# non-root: the official image ships the `nginx` user; listen on an unprivileged port
RUN chown -R nginx:nginx /var/cache/nginx /etc/nginx/conf.d && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx
EXPOSE 8080
