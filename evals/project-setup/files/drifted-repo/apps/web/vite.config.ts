// The one Vite config for a single-frontend product. Served at /, so base is "/". One key per value, read directly,
// no literal fallback: a missing key throws, so a bare `bun dev` without the env exported fails at once.

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

const need = (k: string) => process.env[k] ?? (() => { throw new Error(`${k} is not set — run ctl dev web`); })();

export default defineConfig({
  plugins: [react(), tailwindcss()],
  define: { __APP_NAME__: JSON.stringify("Acme Console") },
  server: {
    port: Number(need("WEB_APP_PORT")),
    proxy: {                                         // mirrors nginx/nginx.conf.template, location for location
      [need("API_PREFIX")]:    { target: `http://127.0.0.1:${need("API_PORT")}`,    changeOrigin: true, ws: true },
    },
  },
});

// A backend on another server: set API_HOST in .env.proxy and use
`https://${need("API_HOST")}:${need("API_PORT")}` as the target. Still no change in the app code.
