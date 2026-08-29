// The one Vite config for a single-frontend product. Served at `/`, so no `base`.
//
// Dev proxy — the reason no nginx is needed in dev. It mirrors nginx.conf.template in this folder
// location for location, so the browser sees one origin in both modes and the code calls `/api/…`:
//
//   import { defineConfig } from "vite";
//   import react from "@vitejs/plugin-react";
//   import tailwindcss from "@tailwindcss/vite";
//
//   const api    = `http://127.0.0.1:${process.env.API_PORT    ?? "8000"}`;
//   const engine = `http://127.0.0.1:${process.env.ENGINE_PORT ?? "8080"}`;
//
//   export default defineConfig({
//     plugins: [react(), tailwindcss()],
//     server: {
//       port: Number(process.env.WEB_APP_PORT ?? 5173),
//       proxy: {
//         [process.env.API_PREFIX    ?? "/api"]:    { target: api,    changeOrigin: true, ws: true },
//         [process.env.ENGINE_PREFIX ?? "/engine"]: { target: engine, changeOrigin: true, ws: true },
//       },
//     },
//   });
//
// API_PORT / ENGINE_PORT / *_PREFIX come from the process env, which `ctl dev` filled from the root .env.
// They are never VITE_* and never reach the bundle. Bare `bun dev` needs them exported first.
// A backend on another server (03_setup.md case 2): set API_HOST in the root .env and use
//   `https://${API_HOST}:${API_PORT}` as the target — still no change in the code.
