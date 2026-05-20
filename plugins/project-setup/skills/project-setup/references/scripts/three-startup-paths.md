# Three startup paths in every README

Every project's README must explain **three ways** to start the stack:

1. **Wrapper script (preferred)** — `./dev`
2. **Raw docker compose** — `docker compose -f docker/compose.<mode>.yaml up`
3. **No docker, host run** — `cd apps/backend && uv run …; cd apps/frontend && bun dev`

Why three? Each serves a different need:

| Path | Why someone uses it |
|---|---|
| `./dev` | Fast onboarding, day-to-day flow |
| Raw compose | Understanding what `./dev` is actually doing; debugging compose itself |
| No-docker | IDE debugger attach; profiling; running tests against a single service in isolation |

If any of the three is broken or missing, the project has accumulated invisible debt.

## Template README section

```markdown
## Get started

```bash
# 1. clone, install runtimes
git clone <url> && cd <repo>
mise install

# 2. configure
cp .env.example .env
# fill in REQUIRED blanks — see comments at the top

# 3. start
./dev
```

### Other ways to start

#### Raw docker compose

```bash
# only databases, apps on host
docker compose -f docker/compose.database-only.yaml up -d

# everything in containers (with host ports)
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up -d

# production
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml --env-file .env.production up -d
```

#### No docker — host run

```bash
# 1. start postgres + redis somewhere — locally installed or compose
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
```
```

## What about prod?

A separate "Deploy" section in the README. Keep startup-for-development distinct from deployment.

## Audit rule

`/ps-setup audit` should check the README for evidence of all three paths. Flag drift:

- README only documents `./dev` → user can't debug compose issues
- README only documents `docker compose` → no fast iteration story
- README only documents raw host run → no convention; everyone reinvents

## Anti-patterns

- "Just run `make dev`" with no explanation of what it does — opaque
- Five-step screenshots of an IDE — instructions rot; text doesn't
- A "Getting Started" doc in a wiki separate from the README — keep the contract in the repo
- Different commands in CI vs in README — CI must use the same documented commands (or a superset)
