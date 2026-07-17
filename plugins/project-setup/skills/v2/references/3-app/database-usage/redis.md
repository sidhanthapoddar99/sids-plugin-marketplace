# Redis usage conventions

How to run Redis well for sessions, caching, pub/sub, and Redis Streams: compose block, auth, AOF durability, db-number separation, Streams tuning, backup. **Whether** to reach for Redis at all (vs an in-process dict) is a choice owned by `references/2-repo/databases-provisioning.md`.

> **Versions in this file are illustrative, not prescriptive.** `redis:7-alpine` reflects what was current at write-time. When `/ps-setup` runs, **check the latest stable version** (`docker pull redis:latest && docker inspect redis:latest --format '{{.RepoTags}}'`, or the official Docker Hub page) and **ask the user** which to pin to. Same applies to every image referenced below.

## Compose service block

```yaml
services:
  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-redis
    restart: unless-stopped
    command: >
      redis-server
        --requirepass ${REDIS_PASSWORD}
        --appendonly yes
        --appendfsync everysec
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR:-./data}/redis/data:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a $$REDIS_PASSWORD ping | grep -q PONG"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 5s
    networks:
      - internal
```

Notes:

- `$$REDIS_PASSWORD` in the healthcheck (double-dollar) escapes compose interpolation so the var is resolved inside the container at runtime
- AOF + `appendfsync everysec` is the durability/perf sweet spot
- `--requirepass` is REQUIRED — running redis without auth on a shared network is a vulnerability even in dev

State bind-mounts under `data/` — placement doctrine owned by `references/2-repo/databases-provisioning.md`.

## Connection string

```yaml
# apps/backend/config.yaml
redis:
  url: redis://default:${REDIS_PASSWORD}@redis:6379/0
  pool_size: 10
```

Standard Redis URL format. `default` is the implicit user when only `requirepass` is set.

## Multiple databases (db numbers)

Use Redis's `db` parameter for soft separation:

| Use | DB |
|---|---|
| Sessions | 0 |
| Application cache | 1 |
| Rate limits | 2 |
| Pub/sub / Streams | 3 |
| Background job queue | 4 |
| Test (CI) | 15 |

Each consumer specifies the db in its URL: `redis://default:pwd@redis:6379/2`.

## Redis Streams (cross-service events)

When using Streams for event-driven flows:

```yaml
redis:
  command: >
    redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --appendfsync everysec
      --maxmemory 2gb
      --maxmemory-policy noeviction      # critical for streams — don't evict events
```

`noeviction` is essential. Default LRU eviction will drop unread stream entries.

## Backup

```bash
# scripts/backup-redis.sh
docker compose exec -T redis sh -c 'redis-cli -a "$REDIS_PASSWORD" BGSAVE'
sleep 5
cp data/redis/data/dump.rdb "backups/$(date +%F)_redis.rdb"
```

For AOF, copy `appendonlydir/`:

```bash
rsync -a data/redis/data/appendonlydir/ remote:backups/redis-aof/
```

## Local dev — pick a db

In dev, pick a db number not used by other projects to avoid collisions on a shared local redis:

```yaml
# apps/backend/config.local.yaml
redis:
  url: redis://default:${REDIS_PASSWORD}@localhost:6379/13   # arbitrary; per-project
```

(Only relevant if you run a single host-level redis across projects.)

## Anti-patterns

- No `--requirepass` "because dev" — vulnerability becomes a habit
- Default eviction policy with Streams — silently loses events
- `latest` tag — pin major version (`redis:7-alpine`)
- One redis per service when one shared redis with different DBs would do — extra moving parts
- Storing large blobs in redis — use SeaweedFS / S3 (see `references/3-app/database-usage/other-engines.md`)
- No persistence (no AOF, no RDB) — restarts wipe state
- Adding Redis for a single-worker app's cache when a dict would do — the in-memory-vs-Redis choice is owned by `references/2-repo/databases-provisioning.md`

## See also

- `references/2-repo/databases-provisioning.md` — in-process memory vs Redis (the choice), coupled to worker count
- `references/3-app/backend/serving.md` — why worker count drives the cache decision
- `references/3-app/database-usage/postgres.md`
