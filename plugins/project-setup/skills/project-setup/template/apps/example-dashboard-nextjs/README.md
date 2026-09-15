# dashboard — Next.js, SSR server

The signed-in dashboard, served at `${DASHBOARD_PREFIX}` (`/dashboard`). Runs as a Node server
(`output: "standalone"`) in its own image; the `web` edge proxies to it. Server components fetch `api`
by service name; the browser uses `/api` on the same origin.

Run from here: `ctl dev dashboard`. Prefix: `DASHBOARD_PREFIX` from `.env`. No `.env` here;
server-side `API_HOST`/`API_PORT` come from `.env` under `ctl dev`, from compose under docker. Test: `bun test`.
`src/app/` is the routing folder; `src/layout/`, `src/modules/`, `src/components/`, `src/lib/` follow the shape in `05_frontend.md`. A page is a server component that mounts one module; a module that holds state marks itself `"use client"`.
