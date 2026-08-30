# <project>

One paragraph: what this product is and which apps make it.

## Prerequisites
- `mise install` — installs every toolchain pinned in `.mise.toml`
- `ctl setup` — creates `.env.secrets`, `.env.data`, `.env.proxy` from their `.template` files, generates secrets, creates `data/*` and `logs/*`

## Quick start with ctl
- `ctl dev` — databases in docker, apps on the host (`--proxy` for one origin across frontends)
- `ctl up` — full stack in docker, the web edge on 80/443
- `ctl migrate` — apply schema migrations
- `ctl gate` — the test ladder; green here is the only definition of green

## Commands
| Verb | Does |
|---|---|
| `ctl dev [app…] [--proxy]` | engines in docker, the chosen apps on the host with reload |
| `ctl up [+modifier…] [--services a,b]` | the stack in docker, or a subset; interactive in a terminal |
| `ctl migrate [new "<msg>"]` | apply or create a migration |
| `ctl manage ops\|settings` | the break-glass operator console |
| `ctl test [app\|e2e]` · `ctl gate [-q]` | one suite, or the whole ladder |
| `ctl setup` · `ctl check` · `ctl status` | create env files and deps · the conformance floor · the doctor |

`ctl --help` is the full list and is always current; this table is a summary.

## Manual, without ctl
Each app's `README.md` shows how to run it from its own folder, the env keys it reads, and how to test it.

## Stack
| Area | Pick |
|---|---|
| Backend | Python `<version>` / FastAPI · Rust `<version>` / Axum · Go `<version>` (CLI) |
| Frontend | TypeScript, Vite `<version>`, Next.js `<version>`, Astro `<version>`, Tailwind v4, shadcn |
| Data | Postgres `<version>` + pgvector · Redis `<version>` · Neo4j `<version>` |
| Containers | docker compose ≥ 2.24; engines in docker for dev, everything for prod |
| Config | `.env.secrets` / `.env.data` / `.env.proxy` + per-backend `config.yaml` |
| Dev | mise · uv · bun · lefthook |

## Documentation
`docs/` when this repo is the docs home (`agent-ks`); otherwise the docs repo is named in `AGENTS.md`.

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
