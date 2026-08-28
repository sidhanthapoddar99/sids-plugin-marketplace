// base: VITE_BASE_PATH. Dev proxy mirrors apps/infra/nginx/nginx.conf so the browser sees one origin:
//   /api    → http://${API_HOST}:${API_PORT}
//   /engine → http://${ENGINE_HOST}:${ENGINE_PORT}   (ws: true)
// Targets are read from ../../.env at config time. They are never VITE_* and never reach the bundle.
