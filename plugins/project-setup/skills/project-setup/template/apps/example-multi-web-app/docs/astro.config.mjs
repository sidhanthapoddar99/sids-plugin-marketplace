// Astro static site. base comes from .env.proxy, read directly, no fallback:
//   const base = process.env.WEB_DOCS_PREFIX; if (!base) throw new Error("WEB_DOCS_PREFIX is not set — run ctl dev docs");
//   export default defineConfig({ base, output: "static" });
// Dev: process env (ctl dev exports .env.proxy). Build: compose build arg WEB_DOCS_PREFIX.
