# Topology 02 — monorepo, 1 backend + 1 frontend

The common product case. One backend, one frontend, in one repo. Examples: `NeuraSutra`, most small-to-medium SaaS products.

## When it fits

- Single backend (Python/Rust/Go/Node)
- Single frontend (Vite + React, or Next.js, or Astro)
- Shared infra (postgres + redis usually)
- One team, one release cadence

## Tree

```
my-app/
├── .env                            # shared vars only (gitignored)
├── .env.example                    # the contract (committed)
├── .env.production                 # optional, compose env_file for prod
├── .mise.toml                      # runtime contract
├── ctl                             # ctl — single dispatcher
├── docker/
│   ├── compose.yaml                # base — no host ports
│   ├── compose.database-only.yaml  # postgres + redis only, for dev mode
│   ├── compose.dev.yaml            # +ports overlay
│   ├── compose.prod.yaml           # production overrides
│   ├── compose.traefik.yaml        # external Traefik overlay
│   └── compose.no-ports.yaml       # prod-behind-reverse-proxy overlay
├── scripts/                        # subscripts the wrapper calls
│   ├── db-init.sh
│   ├── check-env.sh
│   └── …
├── apps/                           # 2+ services → grouped under apps/
│   ├── backend/                    # (name is free: api / backend / …)
│   │   ├── pyproject.toml + uv.lock          # modern Python flow
│   │   ├── config.yaml                       # per-service; reads root .env via ${VAR}
│   │   ├── config.local.yaml                 # gitignored override
│   │   ├── alembic/
│   │   │   ├── env.py
│   │   │   ├── versions/
│   │   │   └── alembic.ini
│   │   ├── alembic.ini
│   │   ├── app/                              # ← FLAT — run-service, no src/
│   │   │   ├── main.py
│   │   │   ├── api/
│   │   │   ├── core/
│   │   │   ├── models/
│   │   │   └── …
│   │   ├── tests/
│   │   ├── Dockerfile
│   │   └── README.md                         # ← this backend's host dev loop
│   └── frontend/                   # (name is free: web / frontend / …)
│       ├── package.json + bun.lockb
│       ├── .env                              # ← frontend's OWN env (VITE_* only)
│       ├── .env.example
│       ├── config.yaml                       # build/dev metadata (optional)
│       ├── vite.config.ts                    # proxies /api/* in dev
│       ├── tailwind.config.ts
│       ├── tsconfig.json
│       ├── src/                              # ← src/ — bundler convention
│       │   ├── styles/
│       │   │   ├── tokens.css                # ← single source of design tokens
│       │   │   ├── globals.css
│       │   │   └── elements.css
│       │   ├── components/
│       │   ├── lib/
│       │   └── pages/
│       ├── Dockerfile
│       └── README.md                         # ← this frontend's host dev loop
├── infra/                          # CONFIG only (not data)
│   ├── nginx/
│   │   └── nginx.conf              # routes /api/* to backend in prod
│   ├── postgres/
│   │   └── init/01_extensions.sql  # CREATE EXTENSION ...
│   └── traefik/
│       └── dynamic.yaml            # reference — only used if Traefik is in scope
├── data/                           # bind-mount targets, gitignored except .gitkeep
│   ├── postgres/
│   │   └── pgdata/.gitkeep         # nested for postgres-empty-dir requirement
│   └── redis/
│       └── data/.gitkeep
├── docs/                           # documentation-template via /docs-init
├── .claude/                        # empty initially
├── CLAUDE.md
├── README.md
└── LICENSE
```

## Key conventions

### Env split

- **`.env`** — shared backend/infra vars (POSTGRES_*, REDIS_*, JWT_*, DOMAIN, ports)
- **`.env.production`** — same keys, prod values; loaded into containers as `env_file`
- **`apps/frontend/.env`** — `VITE_*` only. Examples: `VITE_API_BASE_URL=/api`, `VITE_APP_NAME=My App`. **Never** secrets — these end up in the bundle.

### Config

- **`apps/backend/config.yaml`** — non-secret backend config; reads root `.env` via `${VAR}` interpolation
- **`apps/backend/config.local.yaml`** — gitignored override; takes precedence in dev
- **`apps/frontend/config.yaml`** — usually small; build/dev metadata if any

### Dev flow

- `ctl dev` — host dev loop: auto-ups the data containers (postgres+redis), installs deps (uv sync, bun install), then starts three processes on host (uvicorn --reload, bun dev, optional nginx). Foreground; Ctrl-C stops. Apps run on the host, not in containers.
- `ctl up` — start just the data containers (postgres+redis); `ctl down` to stop them
- `ctl prod` — full stack in docker (prod overlay + traefik), detached
- `ctl migrate {up|down|new "<msg>"}` — alembic (run after first `ctl dev` to apply schema; not done silently)
- `ctl test` — pytest + bun test
- `ctl clean` — `docker compose down -v` + clear caches (asks first)
- `ctl help` — print contract

### Compose overlays

```bash
# dev — apps on host, only DBs in containers (what `ctl dev` / `ctl up` use)
docker compose -f docker/compose.database-only.yaml up -d

# full stack in docker — dev-parity overlay (via `ctl up --prod` style runs)
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up -d

# prod — behind external Traefik (what `ctl prod` runs)
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml up -d
```

The dispatcher picks the right combination: `ctl dev`/`ctl up` for data-only, `ctl prod` for the full stack.

### README

Documents three startup paths:

1. `ctl dev` — preferred
2. Raw `docker compose -f docker/compose.dev.yaml up` — for understanding
3. No-docker host run — for IDE debugging (each service has its own setup snippet)

## What's different from Topology 03

- Single backend, so one `apps/backend/`
- No language coordination concerns
- `ctl` has one set of build steps

## What's different from Topology 04

- Single frontend, no `packages/`, no workspace tool needed
- Tokens live in `apps/frontend/src/styles/tokens.css`, not `packages/styles/`

## Real-world reference

- `NeuraSutra/neurasutra-api-management` — `~/projects/06_04_NeuraSutra/neurasutra-api-management` — close to this pattern; compose files are at root rather than in `docker/` (older convention; ok to migrate when revisited).

## Production serving

The dev flow runs `uvicorn --reload`; production runs gunicorn + uvicorn workers with recycling, behind nginx. The `apps/backend/Dockerfile` `CMD` and the `docker/compose.prod.yaml` overlay differ from dev. See:

- `references/architecture/production/app-server-and-workers.md` — worker count, `--max-requests` recycling, timeouts, preload, the per-language concurrency model
- `references/architecture/production/production-readiness.md` — liveness/readiness endpoints, graceful shutdown, resource limits, migrations-on-deploy, the pre-deploy checklist

## Escalation triggers

- Add a second backend → Topology 03
- Add a second frontend that shares any code → Topology 04
- Add another repo that depends on this one → Topology 06 (aggregator)
