import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";

const need = (key: string) => {
  const value = process.env[key];
  if (!value) throw new Error(`${key} is not set — run through ctl dev`);
  return value;
};

const route = (prefix: string) =>
  `^${prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:/|$)`;

export default defineConfig(({ command }) => ({
  envDir: false,
  base: "/",
  plugins: [tanstackRouter({ target: "react", autoCodeSplitting: true }), react(), tailwindcss()],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  define: { __APP_NAME__: JSON.stringify("<display name>") },
  server: command === "serve" ? {
    host: "127.0.0.1",
    port: Number(need("WEB_APP_PORT")),
    strictPort: true,
    proxy: {
      [route(need("API_PREFIX"))]: {
        target: `http://${need("API_HOST")}:${need("API_PORT")}`,
        changeOrigin: true,
        ws: true,
      },
      [route(need("ENGINE_PREFIX"))]: {
        target: `http://${need("ENGINE_HOST")}:${need("ENGINE_PORT")}`,
        changeOrigin: true,
        ws: true,
      },
    },
  } : undefined,
}));
