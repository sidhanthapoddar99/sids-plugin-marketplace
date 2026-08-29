# dashboard — Next.js, SSR server

The signed-in dashboard, served at `${DASHBOARD_PREFIX}` (`/dashboard`). Runs as a Node server
(`output: "standalone"`) in its own image; the `web` edge proxies to it. Server components fetch `api`
by service name; the browser uses `/api` on the same origin.

Run from here: `bun install && bun dev`. Env: `.env` (`NEXT_PUBLIC_*` only; server-side `API_HOST`/`API_PORT`
come from the root `.env` under `ctl dev`, from compose under docker). Test: `bun test`.
