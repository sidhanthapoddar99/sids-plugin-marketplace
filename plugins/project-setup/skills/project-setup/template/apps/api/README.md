# api — FastAPI

Identity, business logic, everything that writes to Postgres. Owns auth and issues JWTs.

Run from here: `uv sync && uv run uvicorn app.main:app --reload`. Reads `../../.env` and `config.yaml`.
Env keys: see `config.yaml`. Test: `uv run pytest`.
