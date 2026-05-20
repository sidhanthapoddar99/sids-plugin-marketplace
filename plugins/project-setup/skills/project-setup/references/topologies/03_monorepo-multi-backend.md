# Topology 03 — monorepo, multi-backend microservices

Multiple backends in different languages, coordinating via Redis/DB, in one repo. Example: `atheneum` (Python control plane + Rust data plane).

## When it fits

- 2+ backends with **distinct responsibilities** (not just "split for the sake of it")
- Backends are in **different languages** (most common driver) or have **different performance/lifecycle requirements**
- They coordinate over a **shared transport** — Postgres, Redis, Redis Streams, or HTTP
- Single team can release them together (otherwise → Topology 06)

## Tree

```
my-app/
├── .env / .env.example              # shared infra creds + per-service-named vars
├── .mise.toml                       # all language toolchains
├── dev                              # ./dev — language-aware subcommands
├── docker/                          # same overlay set as Topology 02
├── scripts/
├── apps/
│   ├── backend-python/              # control plane
│   │   ├── pyproject.toml + uv.lock
│   │   ├── config.yaml
│   │   ├── alembic/                 # ← migrations live here; ONLY Python writes DDL
│   │   ├── src/<package>/
│   │   ├── tests/
│   │   └── Dockerfile
│   ├── backend-rust/                # data plane
│   │   ├── Cargo.toml + Cargo.lock
│   │   ├── rust-toolchain.toml
│   │   ├── config.yaml
│   │   ├── crates/
│   │   │   ├── api/                 # Axum routes
│   │   │   ├── data/                # sqlx queries (offline-checked)
│   │   │   ├── auth/
│   │   │   ├── sync/
│   │   │   ├── search/
│   │   │   ├── indexer/
│   │   │   └── common/
│   │   ├── .sqlx/                   # offline metadata, committed
│   │   └── Dockerfile
│   └── frontend/                    # optional — same shape as Topology 02
├── infra/  data/  docs/  .claude/   # same as Topology 02
└── README.md / CLAUDE.md
```

## Coordination rules (the skill encodes these)

When two backends coordinate, **one owns the schema, the other consumes**:

- Pick the **DDL owner** explicitly and document.
- The non-owner reads the migrated schema. **It never writes DDL.**
- Coordination happens via Postgres (LISTEN/NOTIFY), Redis (pub/sub, streams), or HTTP — not via direct concurrent writes.

**Atheneum's rule**: Python owns Alembic, Rust never writes DDL. If a Rust query needs a column, write the Alembic migration first, regenerate `.sqlx/`, then add the query. The `./dev` wrapper enforces this — `migrate up → sqlx prepare --check → cargo build` in order, fails locally on drift.

## Env naming

When there are multiple backends, namespace env vars by service when ambiguous:

- `PYTHON_HOST`, `PYTHON_PORT`, `PYTHON_WORKERS`
- `RUST_HOST`, `RUST_PORT`
- `DATABASE_URL` shared
- `REDIS_URL` shared
- `JWT_SIGNING_KEY` shared (if both validate)

## `./dev` subcommands (atheneum pattern)

```
./dev                            # full first-run flow
./dev migrate new "<msg>"        # alembic revision + .up.sql/.down.sql shim
./dev migrate {up|down|status}
./dev sqlx-prepare               # refresh Rust offline metadata
./dev test                       # bun test + pytest + cargo test
./dev clean                      # asks first
./dev help
```

## Compose

Same overlay set as Topology 02. Each backend gets its own service in `compose.yaml`:

```yaml
services:
  backend-python:
    build: ./apps/backend-python
    ...
  backend-rust:
    build: ./apps/backend-rust
    ...
  postgres: ...
  redis: ...
```

## Real-world reference

- `atheneum` — `~/projects/02_OpenSource/04_knowledge_management/atheneum` — the canonical example. Sees CLAUDE.md and README.md for the architecture rationale.

## Common mistakes to avoid

- Splitting backends without a clear coordination boundary ("microservice envy")
- Letting both backends own migrations — pick one
- Sharing config between backends via symlinks — each gets its own `config.yaml`, both reading the same root `.env`
- Forgetting `rust-toolchain.toml` — Rust workspaces need it for reproducibility
