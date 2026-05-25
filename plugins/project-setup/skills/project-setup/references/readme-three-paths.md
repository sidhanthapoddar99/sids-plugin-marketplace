# README contract — three startup paths

The README must document three ways to start the project. Same content as `references/scripts/three-startup-paths.md`, surfaced as a top-level convention so the audit checks it.

## The three paths

1. **`./dev`** — the wrapper. The recommended path. One command.
2. **Raw `docker compose -f docker/...`** — for understanding what `./dev` does, debugging compose issues, copy-pasting for production.
3. **No-docker host run** — `cd apps/backend && uv run ...; cd apps/frontend && bun dev` — for IDE debugger attach, profiling, working on a single service in isolation.

## README structure

```markdown
# <project-name>

<one-paragraph elevator pitch>

GitHub: <url>

---

## Architecture (1 paragraph)

<components, how they talk, source-of-truth rules>

---

## Tech stack

| Area | Pick |
|---|---|
| Backend | <language + framework> |
| Frontend | Vite + React (or Next / Astro) |
| Database | Postgres 16 (+ extensions if any) |
| Cache / events | Redis 7+ |
| Migrations | Alembic |
| Containers | Docker + docker-compose for databases |
| Config | Root .env + per-service config.yaml |
| Theme | Light + dark + tokens.css |

---

## Project layout

\`\`\`
<project>/
├── apps/
│   ├── backend/
│   └── frontend/
├── docker/
├── infra/
├── data/
├── docs/
└── ...
\`\`\`

---

## Get started

\`\`\`bash
# clone
git clone <url> && cd <project>

# runtimes
mise install

# configure
cp .env.example .env
# fill REQUIRED blanks — see comments at top

# start
./dev
\`\`\`

Open <frontend URL> and <backend docs URL>.

Subsequent runs: `./dev` (fast — caches preserved). To wipe and restart: `./dev clean`.

---

## Other ways to start

### Raw docker compose

\`\`\`bash
# dev mode A — apps on host, only DBs in containers
docker compose -f docker/compose.database-only.yaml up -d

# dev mode B — everything in containers
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up -d

# prod
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml --env-file .env.production up -d
\`\`\`

### No docker — host run

\`\`\`bash
# 1. databases (compose or locally installed)
docker compose -f docker/compose.database-only.yaml up -d

# 2. backend
cd apps/backend
uv sync
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 8000

# 3. frontend (new terminal)
cd apps/frontend
bun install
bun dev
\`\`\`

---

## Migrations

See `apps/backend/alembic/` for the migration source. Commands:

\`\`\`bash
./dev migrate new "<message>"
./dev migrate up
./dev migrate down
./dev migrate status
\`\`\`

---

## Deploy

See [docs/deploy.md](docs/deploy.md) (or aggregator repo for Topology 06).

---

## Documentation

Full design docs in `docs/`. Run the docs site locally:

\`\`\`bash
cd docs/documentation-template
./start
\`\`\`

---

## License

<MIT / Apache-2.0 / Proprietary>
```

## Two README levels — root and per-service

There are **two kinds of README**, with a clean division of labour:

| README | Scope |
|---|---|
| **Root `README.md`** | Cross-cutting: the three startup paths, architecture overview, `./dev`, where everything lives. |
| **`<service>/README.md`** (one per backend, one per frontend) | That single service's **host (non-Docker) dev loop** — the IDE-debugging path for *this* service. |

**Every backend and every frontend ships its own `README.md`.** The root README tells you how to run the whole stack; the service README tells you how to work on that one service directly on the host (the path a developer attaching a debugger actually takes).

A `<service>/README.md` covers:

```markdown
# <service-name>

<one line: what this service is>

## Run on the host (dev)

\`\`\`bash
# from this directory
uv sync                              # or bun install
cp .env.example .env                 # this service's own env (if it has one)
uv run alembic upgrade head          # if it owns a DB
uv run uvicorn app.main:app --reload --port 8000
\`\`\`

## Required env vars

| Var | Purpose | Where it comes from |
|---|---|---|
| DATABASE_URL | … | root `.env` / this service's `.env` |

## Tests

\`\`\`bash
uv run pytest          # or bun test
\`\`\`

## Migrations (if applicable)

\`\`\`bash
uv run alembic revision -m "…"
uv run alembic upgrade head
\`\`\`
```

The root README's "no-docker host run" section can then be brief and **point at each service's README** for the detail, rather than duplicating it.

## Audit checks for the README

`/ps-setup audit` should check:

- [ ] Project elevator pitch in first paragraph
- [ ] Tech stack table
- [ ] Project layout tree
- [ ] "Get started" section with `mise install` + `cp .env.example .env` + `./dev`
- [ ] "Other ways to start" section with raw docker compose + no-docker host run
- [ ] Migrations section (if Alembic is used)
- [ ] Documentation pointer
- [ ] License mention
- [ ] **Each backend and frontend has its own `README.md`** documenting its host dev loop

Missing any → drift report flags it.

## Anti-patterns

- README only documents `./dev` — opaque, blocks understanding
- README documents only `docker compose up` without mentioning `./dev` — no convention
- Outdated commands in README that don't match `./dev help` — keep in sync
- Hidden setup steps in a separate wiki — concentrate in the README
- Multi-page README via heavy `[!IMPORTANT]` admonitions — keep it scannable
- A service with no README of its own — the host dev loop lives nowhere, and the root README bloats trying to cover every service's specifics
- Duplicating the full host setup in both the root and the service README — root points, service details
