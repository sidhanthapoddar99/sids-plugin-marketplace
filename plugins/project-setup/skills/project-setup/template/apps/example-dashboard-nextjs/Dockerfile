# Stage 1: oven/bun:<version> — ARG NEXT_PUBLIC_APP_NAME, bun install --frozen-lockfile, bun run build.
# Stage 2: node:<version>-slim — copy .next/standalone + .next/static + public, non-root, CMD node server.js.
# API_HOST / API_PORT arrive at runtime from compose `environment:`. No secret at build time.
