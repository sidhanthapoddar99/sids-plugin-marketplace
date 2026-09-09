# multi-web-app/docs — Astro

Documentation site, served at `${WEB_DOCS_PREFIX}` (`/docs`). Static build. `src/pages/` is Astro's routing folder; `src/layout/` and `src/components/` carry the same meaning as in every other frontend (`05_frontend.md`).
Built by `apps/example-multi-web-app/Dockerfile`, served by the `web` nginx image.

Run from here: `ctl dev docs`. Prefix: `WEB_DOCS_PREFIX` from `.env.proxy`. No `.env` here.
