// base: process.env.PUBLIC_BASE_PATH ?? "/docs" — WEB_DOCS_PREFIX from .env.proxy, a build arg under
// `ctl build`, so every asset URL carries the prefix. output: "static". A site title is a literal here.
// vite: { plugins: [tailwindcss()] } from @tailwindcss/vite. No server adapter.
