// Vite config for a static frontend inside the group. One key, read directly: no VITE_ alias, no literal fallback.
//
//   import { fileURLToPath, URL } from "node:url";
//   import { defineConfig } from "vite";
//   import react from "@vitejs/plugin-react";
//   import tailwindcss from "@tailwindcss/vite";
//   import { tanstackRouter } from "@tanstack/router-plugin/vite";   // file routing: src/routes/ → src/routeTree.gen.ts
//
//   const need = (k: string) => process.env[k] ?? (() => { throw new Error(`${k} is not set — run through ctl (ctl dev app), which exports .env.proxy`); })();
//
//   export default defineConfig({
//     base: need("WEB_APP_PREFIX"),                       // .env.proxy → dev: process env; build: compose build arg
//     plugins: [tanstackRouter({ target: "react", autoCodeSplitting: true }), react(), tailwindcss()],   // the router plugin goes first
//     resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },   // "@/…" = src/, the same map as tsconfig paths
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
