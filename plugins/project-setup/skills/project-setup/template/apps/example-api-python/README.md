# api — FastAPI

Identity, business logic, everything that writes to Postgres. Owns auth and issues JWTs.

Run from here: `uv sync && uv run uvicorn app.main:app --reload`. Reads the root `.env` (skip-if-set) and `config.yaml`. Run through `ctl dev api` so they are loaded.
Env keys: see `config.yaml`. Test: `ctl test api`, which starts its throwaway PostgreSQL. With `TEST_DB_WORKERS` above 1 it runs pytest-xdist workers, each with a server and a database of its own (`tests/worker_database.py`); `TEST_DB_WORKERS=1 ctl test api` runs serially.

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
tests/                           database tests; a unit test sits beside its file in app/
├── conftest.py                  the `conn` fixture: this process's test database, rolled back per test
├── worker_database.py           one database per pytest-xdist worker, on that worker's own server
└── owned_database.py            create a worker's database, and drop only one this run created
```

`router → service → repository` inside a slice. Across slices, `service → service` only. A backend with a handful of endpoints stays flat (`routes.py`, `models.py`) until the second domain appears.
