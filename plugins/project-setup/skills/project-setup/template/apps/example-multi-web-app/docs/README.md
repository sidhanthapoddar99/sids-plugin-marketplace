# multi-web-app/docs — Astro

Documentation site, served at `${WEB_DOCS_PREFIX}` (`/docs`). Static build; content in `src/pages/`.
Built by `apps/example-multi-web-app/Dockerfile`, served by the `web` nginx image.

Run from here: `ctl dev docs`. Prefix: `PUBLIC_BASE_PATH` = `WEB_DOCS_PREFIX` from `.env.proxy`. No `.env` here.
