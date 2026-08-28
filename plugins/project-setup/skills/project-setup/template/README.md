# <project>

One paragraph: what this product is and which apps make it.

## Prerequisites
- `mise install` — installs every toolchain pinned in `.mise.toml`
- `cp .env.example .env` then `ctl setup` — fills secrets, creates `data/*`

## Quick start with ctl
- `ctl dev` — databases in docker, apps on the host
- `ctl up` — full stack in docker, nginx on 80/443
- `ctl migrate` — apply schema migrations

## Manual, without ctl
Each app's `README.md` shows how to run it from its own folder.

## Layout
```
apps/      api engine web site cli packages database infra
docker/    compose.db compose.base compose.m.*
scripts/   ctl workers
data/      runtime state, gitignored
memory/    agent rules
```

## Architecture
One paragraph: site (Next.js) at `/`, web (Vite) at `/app`, api (FastAPI) at `/api`, engine (Rust) at `/engine`. nginx fronts all. Postgres, Redis, Neo4j behind.
