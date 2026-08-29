// output: "standalone" for the Docker image. basePath: "/dashboard" (DASHBOARD_PREFIX) — every route and asset under it.
// rewrites(): dev only — /api/* → http://127.0.0.1:${API_PORT}/api/*, mirroring the prod edge. In prod the web
// image routes /api itself and this server never sees it. API_PORT comes from the process env
// (`ctl dev` exports the root .env). Never a NEXT_PUBLIC_ value.
