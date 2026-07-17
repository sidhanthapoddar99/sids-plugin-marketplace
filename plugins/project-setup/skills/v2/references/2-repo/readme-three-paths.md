# README contract — three startup paths

The README must document three ways to start the project. The three paths themselves — including the exact raw `docker compose` / host-run commands — are owned by `references/2-repo/runtime/script-usage.md`; this doc is the **full README contract** (structure, command table, audit checklist) that surfaces them as a top-level convention.

## The shape: Prerequisites → Quick start (ctl) → Manual (no ctl)

The top of the README has three sections, in order:

1. **Prerequisites** — what to install by hand before anything (mise, Docker); `mise install` provides the rest.
2. **Quick start (`ctl`)** — the recommended path, showing **both** surfaces: `ctl dev` (host loop) and `ctl up` (containers). One dispatcher, two run modes.
3. **Manual (without `ctl`)** — the same stack run *without* the dispatcher: raw `docker compose -f docker/…`, and per-service host runs that **defer to each service's own README**. `ctl` is a project-level management layer; the services are **ctl-agnostic** (their READMEs use only native commands), so this is the fallback when you're not using `ctl`.

These map onto the three startup paths the audit enforces — `ctl` (dev + up), raw compose, and no-docker host run — grouped as "with ctl" (quick start) vs "without ctl" (manual). The exact raw `docker compose` / host-run commands are owned by `references/2-repo/runtime/script-usage.md`; paste them from there so the README never drifts.

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

## Prerequisites

- [mise](https://mise.jdx.dev) — pins + installs every runtime; `mise install` provides Python, Node/Bun, etc.
- Docker + Docker Compose v2 — for the data core / containerised stack
- Nothing else by hand — `mise install` provides the language toolchains.

## Quick start (with `ctl`)

\`\`\`bash
git clone <url> && cd <project>
mise install            # runtimes + puts `ctl` on PATH inside the repo
ctl setup               # fills .env, generates secrets, installs deps

ctl dev                 # apps on the host (hot reload) + data core in containers  ← day-to-day
# or run the whole stack in containers:
ctl up                  # interactive: pick config → modifiers → plan → confirm
ctl up --modifier expose   # whole stack, nginx published on $NGINX_PORT
\`\`\`

Open <frontend URL> and <backend docs URL>. Subsequent runs: `ctl dev` (caches preserved); wipe + restart with `ctl clean`. `ctl dev --dry-run` prints exactly what it would run.

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
| `ctl dev [target] [--dry-run]` | Run the stack on the host with hot reload (auto-ups the data core); `--dry-run` prints the exact host commands |
| `ctl up [config] [--modifier "a,b"]` | Start container stack (interactive in a TTY): a standalone `config` replaces base (`data`, `prod`), `--modifier` overlays stack on top (`ctl up prod` = production) |
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

## Manual (without `ctl`)

For when you don't want the dispatcher — debugging compose itself, attaching a debugger to one service, or a host where `ctl` isn't set up. Two ways:

- **Raw `docker compose -f docker/…`** — what `ctl up` assembles under the hood. Don't hand-write the `-f` lines here: the exact commands (with the current `.m.` modifier filenames) are owned by **`references/2-repo/runtime/script-usage.md`** — paste them from there so the README never drifts.
- **Per-service host run** — `cd apps/<service>` and follow **that service's own `README.md`**. Each service README owns its native start commands (`uv run …`, `bun dev`, …) and is **ctl-agnostic** — it never mentions `ctl`, because `ctl` is a project-level layer wrapping these same commands. The root README points; the service READMEs tell.

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

**Every backend and every frontend ships its own `README.md`.** The root README tells you how to run the whole stack; the service README tells you how to work on that one service directly on the host (the path a developer attaching a debugger actually takes). Crucially, a service README is **ctl-agnostic** — it documents only native commands (`uv run …`, `bun dev`), never `ctl`. `ctl` is a project-level wrapper *over* those commands, so a service stays self-contained and portable (it works the same when lifted out of the repo).

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
- [ ] "Prerequisites" section (mise, Docker) and a "Quick start" showing **both** `ctl dev` and `ctl up`
- [ ] "Configuration" section — what goes in root `.env` (shared) vs per-service `.env`/`config.yaml`, copying `.env.example`, `ctl setup`, and `config.local.yaml` overriding `config.yaml`
- [ ] "Commands" section — table enumerating what `ctl` exposes (dev, prod, up/down, ps, logs, status, setup, migrate, test, build, clean)
- [ ] "Manual (without `ctl`)" section: raw docker compose + per-service host run that **defers to each service's README**
- [ ] Migrations section (if Alembic is used)
- [ ] Documentation pointer
- [ ] License mention
- [ ] **Each backend and frontend has its own `README.md`** documenting its host dev loop (ctl-agnostic — native commands only, never `ctl`)

Missing any → drift report flags it.

## Anti-patterns

- README only documents `ctl dev` — opaque, blocks understanding
- README documents only `docker compose up` without mentioning `ctl` — no convention
- Outdated commands in README that don't match `ctl help` — keep in sync
- Hidden setup steps in a separate wiki — concentrate in the README
- Multi-page README via heavy `[!IMPORTANT]` admonitions — keep it scannable
- A service with no README of its own — the host dev loop lives nowhere, and the root README bloats trying to cover every service's specifics
- Duplicating the full host setup in both the root and the service README — root points, service details

## See also

- `references/2-repo/runtime/script-usage.md` — the exact raw `docker compose` / host-run commands the three paths surface
- `references/2-repo/root-and-hygiene.md` — the root-as-index contract the README serves as the index of
- `references/2-repo/00_charter.md` — the repo-level charter this reference serves
