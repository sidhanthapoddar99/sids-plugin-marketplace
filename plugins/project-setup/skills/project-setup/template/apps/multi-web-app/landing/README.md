# multi-web-app/landing — Next.js, static export

The public landing site, served at `/`. SEO pages, pre-rendered at build (`output: "export"`). No server:
the `web` nginx image serves the exported HTML. Built by `apps/multi-web-app/Dockerfile`.

Run from here: `bun install && bun dev`. Env: `.env` (`NEXT_PUBLIC_*` only). Test: `bun test`.
