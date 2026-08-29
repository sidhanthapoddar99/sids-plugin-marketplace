# <project>

One paragraph: what this product is and which apps make it.

## Prerequisites
- `mise install` — installs every toolchain pinned in `.mise.toml`
- `cp .env.example .env` then `ctl setup` — fills secrets, creates `data/*`

## Quick start with ctl
- `ctl dev` — databases in docker, apps on the host (`--proxy` for one origin across frontends)
- `ctl up` — full stack in docker, the web edge on 80/443
- `ctl migrate` — apply schema migrations

## Manual, without ctl
Each app's `README.md` shows how to run it from its own folder.

## Layout
```
apps/      api engine web/{landing,app,docs} dashboard cli packages database infra
docker/    compose.db compose.base compose.dev compose.m.*
scripts/   ctl workers
data/      runtime state, gitignored
memory/    agent rules
```

## Architecture
One paragraph: one origin. landing (Next.js export) at `/`, app (Vite) at `/app`, docs (Astro) at `/docs` — all in the `web` nginx image, which also proxies dashboard (Next.js SSR) at `/dashboard`, api (FastAPI) at `/api`, engine (Rust) at `/engine`. Postgres, Redis, Neo4j behind.
