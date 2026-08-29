# multi-web-app/landing — Next.js, static export

The public landing site, served at `/`. SEO pages, pre-rendered at build (`output: "export"`). No server:
the `web` nginx image serves the exported HTML. Built by `apps/example-multi-web-app/Dockerfile`.

Run from here: `ctl dev landing`. Prefix: `NEXT_PUBLIC_BASE_PATH` = `WEB_LANDING_PREFIX` from `.env.proxy`. No `.env` here. Test: `bun test`.
