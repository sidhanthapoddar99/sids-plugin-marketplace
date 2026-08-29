// base: process.env.VITE_BASE_PATH ?? "/"  — the prefix (WEB_APP_PREFIX) arrives as a build arg from
// .env.proxy under `ctl build`, and from the process env under `ctl dev app`. A display name is a
// literal here (define: { __APP_NAME__: JSON.stringify("<name>") }), never an env value.
// Dev proxy mirrors apps/example-multi-web-app/nginx/nginx.conf.template so the browser sees one origin:
//   ${API_PREFIX}    → http://127.0.0.1:${API_PORT}
//   ${ENGINE_PREFIX} → http://127.0.0.1:${ENGINE_PORT}   (ws: true)
// API_PORT / ENGINE_PORT / *_PREFIX come from the process env, which `ctl dev` filled from .env.proxy.
// They never reach the bundle. Bare `bun dev` needs the three env files exported first — use `ctl dev app`.
// Under `ctl dev --proxy` (several frontends, one origin) the nginx dev proxy routes /api itself and
// the browser never hits this block; it stays so single-frontend `ctl dev app` still works alone.
// plugins: react(), tailwindcss() from @tailwindcss/vite.
