// Vite config for a static frontend inside the group. One key, read directly: no VITE_ alias, no literal fallback.
//
//   import { defineConfig } from "vite";
//   import react from "@vitejs/plugin-react";
//   import tailwindcss from "@tailwindcss/vite";
//
//   const need = (k: string) => process.env[k] ?? (() => { throw new Error(`${k} is not set — run through ctl (ctl dev app), which exports .env.proxy`); })();
//
//   export default defineConfig({
//     base: need("WEB_APP_PREFIX"),                       // .env.proxy → dev: process env; build: compose build arg
//     plugins: [react(), tailwindcss()],
//     define: { __APP_NAME__: JSON.stringify("<display name>") },   // a display name is a literal, not env
//     server: {
//       port: Number(need("WEB_APP_PORT")),
//       proxy: {                                         // mirrors ../nginx/nginx.conf.template. Never hit under ctl dev --proxy.
//         [need("API_PREFIX")]:    { target: `http://127.0.0.1:${need("API_PORT")}`,    changeOrigin: true, ws: true },
//         [need("ENGINE_PREFIX")]: { target: `http://127.0.0.1:${need("ENGINE_PORT")}`, changeOrigin: true, ws: true },
//       },
//     },
//   });
//
// Every value comes from .env.proxy. A missing one throws, so a bare `bun dev` without the env exported fails
// at once instead of running on a guessed port. Nothing here reaches the bundle except `base` and `define`.
