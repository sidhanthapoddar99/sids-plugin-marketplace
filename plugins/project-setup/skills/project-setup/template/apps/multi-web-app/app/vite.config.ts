// base: VITE_BASE_PATH (/app). Dev proxy mirrors apps/infra/nginx/prod.conf.template so the browser sees one origin:
//   /api    → http://127.0.0.1:${API_PORT}
//   /engine → http://127.0.0.1:${ENGINE_PORT}   (ws: true)
// API_PORT / ENGINE_PORT come from the process env, which `ctl dev` filled from the root .env.
// They are never VITE_* and never reach the bundle. Bare `bun dev` needs them exported first.
// Under `ctl dev --proxy` (several frontends, one origin) the nginx dev proxy routes /api itself and
// the browser never hits this block; it stays so single-frontend `ctl dev app` still works alone.
// plugins: react(), tailwindcss() from @tailwindcss/vite.
