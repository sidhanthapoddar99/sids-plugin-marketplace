# multi-web-app/app — Vite SPA

The product UI, served at `${WEB_APP_PREFIX}` (`/app`). Static bundle; no server. Talks to `/api` and `/engine` on its own origin.

Run from here: `bun install && bun dev`. Env: `.env` (public `VITE_*` only). Test: `bun test`, e2e in `e2e/`.
Built by `apps/multi-web-app/Dockerfile` (one stage per frontend), served by the `web` nginx image.
