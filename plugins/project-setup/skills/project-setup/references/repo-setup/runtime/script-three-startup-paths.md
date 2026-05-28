# Three startup paths in every README

Every project's README must explain **three ways** to start the stack:

1. **The `ctl` dispatcher (preferred)** — `ctl dev` (local) / `ctl up [profile…] [--config=…]` (docker)
2. **Raw docker compose** — `docker compose -f docker/compose.yaml --profile <p> up`
3. **No docker, host run** — `cd apps/backend && uv run …; cd apps/frontend && bun dev`

Why three? Each serves a different need:

| Path | Why someone uses it |
|---|---|
| `ctl` | Fast onboarding, day-to-day flow |
| Raw compose | Understanding what `ctl` is actually doing; debugging compose itself |
| No-docker | IDE debugger attach; profiling; running tests against a single service in isolation |

If any of the three is broken or missing, the project has accumulated invisible debt.

## Template README section

````markdown
## Get started

```bash
# 1. clone, install runtimes
git clone <url> && cd <repo>
mise install        # mise also puts `ctl` on PATH inside the repo (see .mise.toml)

# 2. configure
ctl setup           # interactive: fills .env, generates secrets

# 3. run locally (apps on host, DBs in containers)
ctl dev
```

### Other ways to start

#### The dispatcher

```bash
ctl dev                        # local: apps on host (hot reload), data core in containers
ctl up                         # data core in containers (postgres + redis)
ctl up app                     # + app services in containers
ctl up app edge --config=prod  # full stack in docker (production)
ctl status                     # check configuration before running
```

#### Raw docker compose

```bash
# only the data core (no-profile services), apps on host
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d

# add app services in containers, with host ports
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml --profile app up -d

# production (config = prod, modifier = traefik)
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml --profile app --profile edge --env-file .env.production up -d
```

#### No docker — host run

```bash
# 1. start postgres + redis somewhere — locally installed or compose
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d   # data core, ports published

# 2. backend
cd apps/backend
uv sync
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 8000

# 3. frontend (new terminal)
cd apps/frontend
bun install
bun dev
```
````

The no-docker path is what `ctl dev` automates; documenting it raw lets a developer attach a debugger to one service.

## What about prod?

`ctl up app edge --config=prod` is the convention; the README's **Deploy** section documents it plus the raw compose prod command. Keep startup-for-development (`ctl dev`) distinct from deployment (`ctl up … --config=prod`).

## Audit rule

`/ps-setup audit` should check the README for evidence of all three paths. Flag drift:

- README only documents `ctl dev` → user can't debug compose issues
- README only documents `docker compose` → no fast iteration story, no convention
- README only documents raw host run → everyone reinvents the flow

## Anti-patterns

- "Just run `make dev`" with no explanation of what it does — opaque
- Five-step screenshots of an IDE — instructions rot; text doesn't
- A "Getting Started" doc in a wiki separate from the README — keep the contract in the repo
- Different commands in CI vs in README — CI must use the same documented commands (or a superset)
