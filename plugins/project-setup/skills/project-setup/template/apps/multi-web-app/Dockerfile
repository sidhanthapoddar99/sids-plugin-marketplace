# The web image: every static frontend built, one nginx serving them all and proxying the rest.
# Build context is ./apps (needs packages/ and infra/): compose sets `context: ./apps, dockerfile: multi-web-app/Dockerfile`.
# One build stage per frontend. Public build args arrive from apps/multi-web-app/<name>/.env through `ctl build`.
# No secret is ever a build arg — an ARG stays in the image history.

# ---- landing: Next.js static export → out/ ----
FROM oven/bun:<version> AS landing
WORKDIR /src
COPY packages ./packages
COPY multi-web-app/landing ./multi-web-app/landing
ARG NEXT_PUBLIC_SITE_NAME
ENV NEXT_PUBLIC_SITE_NAME=${NEXT_PUBLIC_SITE_NAME}
RUN cd multi-web-app/landing && bun install --frozen-lockfile && bun run build

# ---- app: Vite SPA → dist/ ----
FROM oven/bun:<version> AS app
WORKDIR /src
COPY packages ./packages
COPY multi-web-app/app ./multi-web-app/app
ARG VITE_APP_NAME
ARG VITE_BASE_PATH=/app
ENV VITE_APP_NAME=${VITE_APP_NAME} VITE_BASE_PATH=${VITE_BASE_PATH}
RUN cd multi-web-app/app && bun install --frozen-lockfile && bun run build

# ---- docs: Astro → dist/ ----
FROM oven/bun:<version> AS docs
WORKDIR /src
COPY packages ./packages
COPY multi-web-app/docs ./multi-web-app/docs
ARG PUBLIC_SITE_NAME
ENV PUBLIC_SITE_NAME=${PUBLIC_SITE_NAME}
RUN cd multi-web-app/docs && bun install --frozen-lockfile && bun run build

# ---- edge: nginx serves the three builds and proxies api / engine / dashboard ----
FROM nginx:<version>
# prefixes and upstreams arrive at runtime as env; the nginx image renders *.template with envsubst
COPY infra/nginx/prod.conf.template /etc/nginx/templates/default.conf.template
COPY --from=landing /src/multi-web-app/landing/out/  /usr/share/nginx/html/
COPY --from=app     /src/multi-web-app/app/dist/     /usr/share/nginx/html/app/
COPY --from=docs    /src/multi-web-app/docs/dist/    /usr/share/nginx/html/docs/
# non-root: the official image ships the `nginx` user; listen on an unprivileged port
RUN chown -R nginx:nginx /var/cache/nginx /etc/nginx/conf.d && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx
EXPOSE 8080
