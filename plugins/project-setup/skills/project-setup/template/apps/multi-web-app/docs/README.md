# multi-web-app/docs — Astro

Documentation site, served at `${WEB_DOCS_PREFIX}` (`/docs`). Static build; content in `src/pages/`.
Built by `apps/multi-web-app/Dockerfile`, served by the `web` nginx image.

Run from here: `bun install && bun dev`. Env: `.env` (`PUBLIC_*` only — Astro's public prefix).
