# multi-web-app/app — Vite SPA

The product UI, served at `${WEB_APP_PREFIX}` (`/app`). Static bundle; no server. Talks to `/api` and `/engine` on its own origin.

Run from here: `ctl dev app` (exports the env files, then `bun dev`). Prefix: `VITE_BASE_PATH` = `WEB_APP_PREFIX` from `.env.proxy`. No `.env` here. Test: `bun test`, e2e in `e2e/`.
Built by `apps/example-multi-web-app/Dockerfile` (one stage per frontend), served by the `web` nginx image.
