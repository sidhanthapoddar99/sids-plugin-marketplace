# Postgres conventions

The default relational database for new projects.

> **Versions in this file are illustrative, not prescriptive.** `postgres:16-alpine`, `pgvector/pgvector:pg16` reflect what was current at write-time. When `/ps-setup` runs, **check the latest stable version** and **ask the user** which to pin to. Major-version upgrades have migration implications — the user should choose deliberately, not inherit a stale default from this file.

## Image

```yaml
services:
  postgres:
    image: postgres:16-alpine          # plain
    # OR for pgvector:
    # image: pgvector/pgvector:pg16
```

Defaults: `pgvector/pgvector:pg16` if the project might want vector search (cheap insurance — extension stays unused until you `CREATE EXTENSION`).

## Compose service block

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --locale=C.UTF-8"
    volumes:
      - ${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data
      - ../infra/postgres/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s
    networks:
      - internal
```

## Init scripts (`infra/postgres/init/`)

Run once on first boot (empty `pgdata`). For extensions, base roles, etc.

```sql
-- infra/postgres/init/01_extensions.sql
CREATE EXTENSION IF NOT EXISTS pgvector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS cube;
```

```sql
-- infra/postgres/init/02_roles.sql
-- if you need a read-only role for analytics
CREATE ROLE myapp_ro;
GRANT CONNECT ON DATABASE myapp TO myapp_ro;
GRANT USAGE ON SCHEMA public TO myapp_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO myapp_ro;
```

Numbered prefixes ensure ordering.

## Connection string

In `apps/backend/config.yaml`:

```yaml
database:
  url: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  pool_size: 20
  pool_max_overflow: 10
```

`postgres` is the compose service name; inside compose's internal network it resolves automatically.

## Healthcheck pattern

`pg_isready` is the standard. Wait for healthy before starting backend:

```yaml
backend:
  depends_on:
    postgres:
      condition: service_healthy
```

## Backup approach (compose-on-VM era)

```bash
# scripts/backup-postgres.sh
mkdir -p backups
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "backups/$(date +%F)_${POSTGRES_DB}.sql.gz"
```

Plus `rsync data/postgres/pgdata/ remote:backups/pgdata/` for filesystem-level snapshots (with the service stopped).

## Common extensions per use case

| Use case | Extension |
|---|---|
| Vector embeddings | `pgvector` |
| Fuzzy search | `pg_trgm` |
| Partitioning helpers | `pg_partman` |
| UUIDv4 (default Postgres 13+: `gen_random_uuid()` from pgcrypto) | `pgcrypto` |
| Range / multidimensional indexes | `cube` |
| Hierarchical / graph-ish queries | `ltree` |

## Anti-patterns

- Running `Base.metadata.create_all()` in production — migrations should be explicit
- Hardcoding the DSN — read from config + env
- Skipping healthchecks — race conditions
- Using `latest` tag — pin major version
- Storing the password literal in `config.yaml` — `${POSTGRES_PASSWORD}` from root `.env`
- Forgetting `POSTGRES_INITDB_ARGS` locale — collation drift between systems
- Bind-mounting `data/postgres/` directly (with `.gitkeep` inside) — initdb fails; use nested `pgdata/`
