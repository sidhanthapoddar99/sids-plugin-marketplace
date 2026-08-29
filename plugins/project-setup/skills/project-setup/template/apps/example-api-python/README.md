# api — FastAPI

Identity, business logic, everything that writes to Postgres. Owns auth and issues JWTs.

Run from here: `uv sync && uv run uvicorn app.main:app --reload`. Reads the root `.env.secrets` / `.env.proxy` (skip-if-set) and `config.yaml`. Run through `ctl dev api` so they are loaded.
Env keys: see `config.yaml`. Test: `uv run pytest`.

## Layout

```
app/
├── main.py  config.py  db.py    composition · the one loader · the pool
├── core/                        cross-cutting: security, redis, rate limit
├── health/                      /health and /ready
└── <domain>/                    users/ workspaces/ … one slice each
    ├── models.py                request/response schemas (the contract)
    ├── repository.py            SQL; takes a connection, caller owns the transaction
    ├── service.py               the rules; the domain's public surface
    └── router.py                thin HTTP: parse, auth, call, return
```

`router → service → repository` inside a slice. Across slices, `service → service` only. A backend with a handful of endpoints stays flat (`routes.py`, `models.py`) until the second domain appears.
