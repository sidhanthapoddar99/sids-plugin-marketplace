# `infra/` (config) vs `data/` (state)

Two top-level folders, two different purposes. Easy to conflate; keep distinct.

## `infra/` — config baked into containers

Read-only at runtime. Mounted into containers as ConfigMap-equivalents. Committed.

```
infra/
├── nginx/
│   └── nginx.conf
├── postgres/
│   └── init/
│       └── 01_extensions.sql        # mounted to /docker-entrypoint-initdb.d
├── redis/
│   └── redis.conf
├── traefik/
│   └── dynamic.yaml                  # reference — only used if Traefik is in scope
└── seaweed/
    └── filer.toml
```

## `data/` — state mounted from host

Read-write at runtime. Bind-mount targets. Gitignored (except `.gitkeep`).

```
data/
├── postgres/
│   └── pgdata/                       # bind-mounted; first-run-empty
├── redis/
│   └── data/                         # AOF file
├── seaweed/
│   ├── master/
│   ├── volume/
│   └── filer/
└── meili/
    └── data.ms/
```

## Why split

| `infra/` | `data/` |
|---|---|
| Committed | Gitignored |
| Read-only inside container | Read-write inside container |
| Code-reviewed | Operational |
| Migration target during ops | Backup target during ops |

Putting nginx.conf and postgres data in the same `postgres/` folder makes review/backup workflows confused. Keep concerns physically separate.

## compose references both

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    volumes:
      # data (mutable)
      - ${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data
      # infra (read-only config)
      - ../infra/postgres/init:/docker-entrypoint-initdb.d:ro

  nginx:
    image: nginx:1.27-alpine
    volumes:
      - ../infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
```

The `:ro` (read-only) flag on infra mounts is the discipline marker.

## `.gitignore`

```
# data — gitignore everything except .gitkeep markers
data/
!data/.gitkeep
!data/**/.gitkeep

# infra is fully committed (no exclusion needed beyond default)
```

## `${DATA_DIR}` override

The compose files use `${DATA_DIR:-./data}` so the actual data location is env-configurable:

- Dev: `./data` (default, in-repo)
- Prod: `/srv/my-app/data` (set in `.env.production`)
- Test: `/tmp/my-app-test-${RUN_ID}` (set in CI)

`infra/` is **always** at `../infra/` relative to `docker/` — not env-configurable. It's source.

## When a service has both config and data

Postgres is the canonical example:

- Config: `infra/postgres/init/01_extensions.sql` (and `postgresql.conf` if customised)
- Data: `data/postgres/pgdata/` (bind-mount, gitignored)

Mount both. Different `:ro` / `:rw` semantics.

## Anti-patterns

- Putting `data/postgres/init/` and `data/postgres/pgdata/` in the same parent — split into `infra/postgres/` and `data/postgres/`
- Committing `data/postgres/pgdata/*` accidentally — `.gitignore` strictly
- Mutating `infra/` files at runtime — they're meant to be code-reviewed and re-deployed
- `infra/` containing secrets — secrets are env vars, not config files
- Different conventions per service in the same repo — be uniform
