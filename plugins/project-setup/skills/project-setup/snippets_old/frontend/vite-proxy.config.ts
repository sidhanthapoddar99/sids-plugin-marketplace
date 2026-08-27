// apps/frontend/vite.config.ts — proxies /api/* to the backend in dev.
// In prod, nginx serves the same role. Frontend code uses /api/* everywhere.

import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const backendPort = env.PYTHON_PORT ?? "8000";

  return {
    plugins: [react()],
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "src"),
      },
    },
    server: {
      port: 5173,
      strictPort: true,
      host: "0.0.0.0",
      proxy: {
        "/api": {
          target: `http://localhost:${backendPort}`,
          changeOrigin: true,
        },
        "/ws": {
          target: `ws://localhost:${backendPort}`,
          ws: true,
        },
      },
    },
    build: {
      outDir: "dist",
      sourcemap: mode !== "production",
    },
  };
});
