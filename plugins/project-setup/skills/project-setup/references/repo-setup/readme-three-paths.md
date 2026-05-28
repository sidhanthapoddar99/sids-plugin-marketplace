# README contract — three startup paths

The README must document three ways to start the project. The three paths themselves — including the exact raw `docker compose` / host-run commands — are owned by `references/repo-setup/runtime/script-usage.md`; this doc is the **full README contract** (structure, command table, audit checklist) that surfaces them as a top-level convention.

## The three paths

1. **`ctl dev`** — the dispatcher. The recommended path. One command runs the stack on the host with hot reload.
2. **Raw `docker compose -f docker/...`** — for understanding what `ctl` does, debugging compose issues, copy-pasting for production.
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
ctl dev
\`\`\`

Open <frontend URL> and <backend docs URL>.

Subsequent runs: `ctl dev` (fast — caches preserved). To wipe and restart: `ctl clean`.

---

## Configuration

| Where | Holds |
|---|---|
| Root `.env` | Shared, cross-service values (DB creds, `POSTGRES_*`, shared ports) |
| `<service>/.env` or `<service>/config.yaml` | Per-service config — that service's own settings |
| `<service>/config.local.yaml` | Local overrides — wins over `config.yaml`, gitignored |

\`\`\`bash
cp .env.example .env       # fill REQUIRED blanks (see comments at top)
ctl setup                  # interactive .env wizard — prompts for missing keys
\`\`\`

`config.local.yaml` overrides `config.yaml` for machine-specific tweaks without touching the committed defaults.

---

## Commands

`ctl` is the single dispatcher. The full surface:

| Command | Does |
|---|---|
| `ctl dev [target]` | Run the stack on the host with hot reload (auto-ups the data core) |
| `ctl up [profile…] [--config=n…]` | Start container stack: profiles select services (bare = data core), `--config` overlays how they run (`ctl up app edge --config=prod` = production) |
| `ctl down [service]` | Stop container services |
| `ctl ps` | List containers + local processes |
| `ctl logs [svc] [-f]` | Tail logs |
| `ctl status [svc]` | Config doctor |
| `ctl setup` | Interactive `.env` wizard |
| `ctl migrate {up\|down\|new\|status}` | Alembic migrations |
| `ctl test [target]` | Run tests |
| `ctl build` | Build images / artifacts |
| `ctl clean` | Wipe caches + volumes (asks first) |
| `ctl help` | Print the contract |

---

## Other ways to start

Besides `ctl dev`, the README's "Other ways to start" carries **two** more paths — raw `docker compose -f …` and a no-docker host run. Don't hand-write the `-f` lines here: the exact commands (with the current `.m.` modifier filenames) are owned by **`references/repo-setup/runtime/script-usage.md`** and kept in sync with the dispatcher. Paste them from there into the generated README so this template never drifts when the compose layout changes.

---

## Migrations

See `apps/backend/alembic/` for the migration source. Commands:

\`\`\`bash
ctl migrate new "<message>"
ctl migrate up
ctl migrate down
ctl migrate status
\`\`\`

---

## Deploy

See [docs/deploy.md](docs/deploy.md) (or aggregator repo for Layout 03).

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
| **Root `README.md`** | Cross-cutting: the three startup paths, architecture overview, `ctl`, configuration, the command table, where everything lives. |
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
- [ ] "Get started" section with `mise install` + `cp .env.example .env` + `ctl dev`
- [ ] "Configuration" section — what goes in root `.env` (shared) vs per-service `.env`/`config.yaml`, copying `.env.example`, `ctl setup`, and `config.local.yaml` overriding `config.yaml`
- [ ] "Commands" section — table enumerating what `ctl` exposes (dev, prod, up/down, ps, logs, status, setup, migrate, test, build, clean)
- [ ] "Other ways to start" section with raw docker compose + no-docker host run
- [ ] Migrations section (if Alembic is used)
- [ ] Documentation pointer
- [ ] License mention
- [ ] **Each backend and frontend has its own `README.md`** documenting its host dev loop

Missing any → drift report flags it.

## Anti-patterns

- README only documents `ctl dev` — opaque, blocks understanding
- README documents only `docker compose up` without mentioning `ctl` — no convention
- Outdated commands in README that don't match `ctl help` — keep in sync
- Hidden setup steps in a separate wiki — concentrate in the README
- Multi-page README via heavy `[!IMPORTANT]` admonitions — keep it scannable
- A service with no README of its own — the host dev loop lives nowhere, and the root README bloats trying to cover every service's specifics
- Duplicating the full host setup in both the root and the service README — root points, service details
