// The one Vite config for a single-frontend product. Served at /, so base is "/". One key per value, read directly,
// no literal fallback: a missing key throws, so a bare `bun dev` without the env exported fails at once.
//
//   import { fileURLToPath, URL } from "node:url";
//   import { defineConfig } from "vite";
//   import react from "@vitejs/plugin-react";
//   import tailwindcss from "@tailwindcss/vite";
//   import { tanstackRouter } from "@tanstack/router-plugin/vite";   // file routing: src/routes/ → src/routeTree.gen.ts
//
//   const need = (k: string) => process.env[k] ?? (() => { throw new Error(`${k} is not set — run ctl dev single`); })();
//
//   export default defineConfig({
//     plugins: [tanstackRouter({ target: "react", autoCodeSplitting: true }), react(), tailwindcss()],   // the router plugin goes first
//     resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },   // "@/…" = src/, the same map as tsconfig paths
//     define: { __APP_NAME__: JSON.stringify("<display name>") },
//     server: {
//       port: Number(need("WEB_APP_PORT")),
//       proxy: {                                         // mirrors nginx/nginx.conf.template, location for location
//         [need("API_PREFIX")]:    { target: `http://127.0.0.1:${need("API_PORT")}`,    changeOrigin: true, ws: true },
//         [need("ENGINE_PREFIX")]: { target: `http://127.0.0.1:${need("ENGINE_PORT")}`, changeOrigin: true, ws: true },
//       },
//     },
//   });
//
// A backend on another server: set API_HOST in .env and use
//   `https://${need("API_HOST")}:${need("API_PORT")}` as the target. Still no change in the app code.
