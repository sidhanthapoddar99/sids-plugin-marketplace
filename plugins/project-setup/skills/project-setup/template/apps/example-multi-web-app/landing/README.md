# multi-web-app/landing — Next.js, static export

The public landing site, served at `/`. SEO pages, pre-rendered at build (`output: "export"`). No server:
the `web` nginx image serves the exported HTML. Built by `apps/example-multi-web-app/Dockerfile`.

Run from here: `ctl dev landing`. Owns `/`: no prefix key. No `.env` here. Test: `bun test`.
`src/app/` is the routing folder; `src/layout/`, `src/modules/`, `src/components/` follow the shape in `05_frontend.md`.
