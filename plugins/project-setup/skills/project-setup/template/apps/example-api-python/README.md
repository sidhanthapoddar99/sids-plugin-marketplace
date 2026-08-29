# api — FastAPI

Identity, business logic, everything that writes to Postgres. Owns auth and issues JWTs.

Run from here: `uv sync && uv run uvicorn app.main:app --reload`. Reads the root `.env.secrets` / `.env.proxy` (skip-if-set) and `config.yaml`. Run through `ctl dev api` so they are loaded.
Env keys: see `config.yaml`. Test: `uv run pytest`.
