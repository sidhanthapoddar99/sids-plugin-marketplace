# acme-console

Internal operations dashboard. Staff sign in and manage users and workspaces. Two apps: `apps/api` (FastAPI) and `apps/web` (Vite + React). Postgres and Redis are the data core.

## Prerequisites

`mise install`, then `ctl setup`.

## Quick start

`ctl dev` runs the engines in docker and both apps on the host. `ctl up` runs everything in docker. `ctl --help` lists every verb.

## Manual

Each app's `README.md` shows how to run it from its own folder without `ctl`.

## Layout

`apps/api`, `apps/web`, `apps/database/postgres`, `docker/`, `scripts/`, `data/`, `logs/`, `memory/`. `AGENTS.md` is the agent brief.
