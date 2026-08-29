# dashboard — Next.js, SSR server

The signed-in dashboard, served at `${DASHBOARD_PREFIX}` (`/dashboard`). Runs as a Node server
(`output: "standalone"`) in its own image; the `web` edge proxies to it. Server components fetch `api`
by service name; the browser uses `/api` on the same origin.

Run from here: `ctl dev dashboard`. Prefix: `NEXT_PUBLIC_BASE_PATH` = `DASHBOARD_PREFIX` from `.env.proxy`. No `.env` here;
server-side `API_HOST`/`API_PORT` come from `.env.proxy` under `ctl dev`, from compose under docker. Test: `bun test`.
