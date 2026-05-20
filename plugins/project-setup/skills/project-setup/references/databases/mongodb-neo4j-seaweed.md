# Other databases — quick reference

## MongoDB

```yaml
services:
  mongodb:
    image: mongo:7
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-mongo
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DB}
    volumes:
      - ${DATA_DIR:-./data}/mongodb/data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal
```

```yaml
# config.yaml
mongo:
  uri: mongodb://${MONGO_USER}:${MONGO_PASSWORD}@mongodb:27017/${MONGO_DB}?authSource=admin
```

Use when: document model fits naturally (nested, schemaless variants). Avoid as a general-purpose RDB substitute.

## Neo4j

```yaml
services:
  neo4j:
    image: neo4j:5-community
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
      NEO4J_server_memory_heap_initial__size: 512m
      NEO4J_server_memory_heap_max__size: 1G
    volumes:
      - ${DATA_DIR:-./data}/neo4j/data:/data
      - ${DATA_DIR:-./data}/neo4j/logs:/logs
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:7474 || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal
```

Use when: graph queries dominate (recommendation engines, social, knowledge graphs). For embedded graph data within a relational system, prefer Postgres + `ltree` or recursive CTEs.

## Kuzu (embedded)

Embedded — no compose service. Used inside the application process. Set up at backend startup; data lives at `${DATA_DIR}/kuzu/`.

```yaml
# config.yaml
kuzu:
  path: ${KUZU_DATA_DIR:-/data/kuzu}
```

Mount `${DATA_DIR}/kuzu` into the backend container.

## SeaweedFS

```yaml
services:
  seaweed-master:
    image: chrislusf/seaweedfs:latest
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-seaweed-master
    command: master -ip=seaweed-master
    volumes:
      - ${DATA_DIR:-./data}/seaweed/master:/data
    networks:
      - internal

  seaweed-volume:
    image: chrislusf/seaweedfs:latest
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-seaweed-volume
    command: volume -mserver=seaweed-master:9333 -ip.bind=0.0.0.0
    volumes:
      - ${DATA_DIR:-./data}/seaweed/volume:/data
    depends_on:
      - seaweed-master
    networks:
      - internal

  seaweed-filer:
    image: chrislusf/seaweedfs:latest
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-seaweed-filer
    command: filer -master=seaweed-master:9333
    volumes:
      - ${DATA_DIR:-./data}/seaweed/filer:/data
      - ../infra/seaweed/filer.toml:/etc/seaweedfs/filer.toml:ro
    depends_on:
      - seaweed-master
      - seaweed-volume
    networks:
      - internal

  seaweed-s3:
    image: chrislusf/seaweedfs:latest
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-seaweed-s3
    command: s3 -filer=seaweed-filer:8888
    depends_on:
      - seaweed-filer
    networks:
      - internal
```

Backend talks S3 protocol to `seaweed-s3:8333`. Cheap, self-hosted blob store.

Use when: image/file uploads, document storage, anywhere you'd reach for S3 but want self-hosted.

## Meilisearch

```yaml
services:
  meilisearch:
    image: getmeili/meilisearch:v1.10
    container_name: ${COMPOSE_PROJECT_NAME:-my-app}-meili
    restart: unless-stopped
    environment:
      MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}
      MEILI_ENV: ${MEILI_ENV:-development}
    volumes:
      - ${DATA_DIR:-./data}/meili/data.ms:/meili_data/data.ms
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7700/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal
```

Use when: fuzzy / full-text search with typo tolerance. Atheneum uses it alongside pgvector (semantic) and pg_trgm (regex).

## General rules

1. **Pin major versions** — never `latest`.
2. **Healthchecks always** — backend `depends_on: { condition: service_healthy }`.
3. **Bind-mount under `data/<service>/`** — gitignored.
4. **Config files under `infra/<service>/`** — committed.
5. **Auth always**, even in dev.
6. **Internal network** unless host port exposure is needed via `compose.dev.yaml` overlay.

## When to pick which

| Need | Pick |
|---|---|
| Relational, ACID, the answer for 80% of cases | Postgres |
| Cache, sessions, pub/sub, streams | Redis |
| Document model where schemas are truly variable | MongoDB |
| Graph queries dominate | Neo4j |
| Embedded graph DB, no separate container | Kuzu |
| Blob storage, S3-compatible, self-hosted | SeaweedFS |
| Fuzzy search with typo tolerance | Meilisearch |
| Vector embeddings | pgvector (Postgres extension) — usually before pulling in a separate vector DB |
| Time-series at scale | TimescaleDB (Postgres extension) before reaching for InfluxDB / Prometheus |

Default to Postgres + Redis. Add others only when there's evidence a Postgres extension can't do the job.
