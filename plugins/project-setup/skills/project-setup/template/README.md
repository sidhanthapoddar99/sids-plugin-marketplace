# <project>

One paragraph: what this product is and which apps make it.

## Prerequisites
- `mise install` — installs every toolchain pinned in `.mise.toml`
- `ctl setup` — creates `.env.secrets`, `.env.data`, `.env.proxy` from their `.template` files, generates secrets, creates `data/*` and `logs/*`

## Quick start with ctl
- `ctl dev` — databases in docker, apps on the host (`--proxy` for one origin across frontends)
- `ctl up` — full stack in docker, the web edge on 80/443
- `ctl migrate` — apply schema migrations

## Manual, without ctl
Each app's `README.md` shows how to run it from its own folder.

## Lock files
The template ships no `bun.lock`, `uv.lock` or `Cargo.lock`: every dependency is a `<version>` placeholder. `ctl setup` installs and creates them. Commit them.

## Layout
```
apps/      example-api-python example-engine-rust example-multi-web-app/{landing,app,docs}
           example-single-web-app-vite example-dashboard-nextjs example-tui-go packages database
docker/    compose.db compose.base compose.dev compose.m.*
scripts/   ctl workers
data/      actual data: engine mounts, datasets. gitignored
logs/      produced state: logs, pids, backups, frozen builds. gitignored
.env.secrets.template  .env.data.template  .env.proxy.template   the env contract (committed); ctl setup makes the real files
memory/    agent rules
```

## Architecture
One paragraph: one origin. landing (Next.js export) at `/`, app (Vite) at `/app`, docs (Astro) at `/docs` — all in the `web` nginx image, which also proxies dashboard (Next.js SSR) at `/dashboard`, api (FastAPI) at `/api`, engine (Rust) at `/engine`. Postgres, Redis, Neo4j behind.
