# multi-web-app/app — Vite SPA

The product UI, served at `${WEB_APP_PREFIX}` (`/app`). Static bundle; no server. Talks to `/api` and `/engine` on its own origin.

Run from here: `ctl dev app` (exports the env files, then `bun dev`). Prefix: `WEB_APP_PREFIX` from `.env.proxy`. No `.env` here. Test: `bun test`. The browser suite (`e2e/`) is an add-on.
`src/` follows the frontend shape in `05_frontend.md`: `routes/` (TanStack Router), `layout/`, `modules/`, `components/`, `lib/`. Primitives and theme come from `@scope/ui`.
Built by `apps/example-multi-web-app/Dockerfile` (one stage per frontend), served by the `web` nginx image.
