// output: "standalone" for the Docker image.
// basePath: process.env.NEXT_PUBLIC_BASE_PATH ?? "/dashboard" — DASHBOARD_PREFIX from .env.proxy, a build
// arg under `ctl build`; every route and asset under it. An app name is a literal in the layout, never env.
// rewrites(): dev only — ${API_PREFIX}/* → http://127.0.0.1:${API_PORT}/… , mirroring the prod edge. In prod the web
// image routes /api itself and this server never sees it. API_PORT comes from the process env
// (`ctl dev` exports the three env files). Server-side fetches read API_HOST/API_PORT the same way; under
// docker compose sets them. Never a NEXT_PUBLIC_ value for a host.
