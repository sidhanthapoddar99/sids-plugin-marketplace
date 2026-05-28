# `docker/` folder layout

All compose files live under `docker/`. Root has at most a `.env` and `.env.example`.

## Standard layout (Topology 02–05)

```
docker/
├── compose.yaml
├── compose.database-only.yaml
├── compose.dev.yaml
├── compose.prod.yaml
├── compose.traefik.yaml
└── compose.no-ports.yaml
```

The `ctl` dispatcher knows which combination to use per mode; users can also invoke compose directly.

## Orchestrator layout (Topology 08)

```
docker/
├── singlenode/
│   └── compose.yaml
├── multinode/
│   ├── compose.yaml
│   ├── compose.no-ports.yaml
│   ├── compose.reset.yaml
│   ├── compose.test-temp.yaml
│   └── compose.traefik.yaml
└── prod/
    └── compose.yaml
```

Each mode is a directory containing its base and overlays.

## Per-service support files

Init scripts, custom configs, certificates that go into a container belong **adjacent to the service**, not in `docker/`:

```
infra/
├── nginx/nginx.conf                        # baked into nginx container
├── postgres/init/01_extensions.sql         # mounted to /docker-entrypoint-initdb.d
└── traefik/dynamic.yaml                    # reference only
```

The compose files reference them with relative paths:

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    volumes:
      - ${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data
      - ../infra/postgres/init:/docker-entrypoint-initdb.d:ro
```

Note the `../` — compose files in `docker/` reference `infra/` and `data/` via parent.

## Path discipline

| Where | Inside compose file |
|---|---|
| Mount a bind from `data/` | `${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data` — `${DATA_DIR}` from `.env`, fallback to `./data` |
| Reference infra config | `../infra/<service>/<file>:/container/path:ro` |
| Build a service | `build: ../apps/<service>` (context one level up) |

Using `${DATA_DIR}` makes it overridable from env — useful in dev (`DATA_DIR=/tmp/my-app-data`) and prod (`DATA_DIR=/srv/my-app/data`).

## Compose working directory

`docker compose` resolves paths relative to the first `-f` file. With `-f docker/compose.yaml`, paths in the compose are relative to `docker/`. That's why `../apps/<service>` and `../infra/<service>` work.

Alternative: invoke from the `docker/` directory with `cd docker && docker compose up`. Either approach is fine; pick one and document it.

## `ctl` handles paths

The user never types those flags. `ctl` runs from repo root and constructs the full `-f` argument list:

```bash
cmd_prod() {
  docker compose \
    -f docker/compose.yaml \
    -f docker/compose.prod.yaml \
    -f docker/compose.traefik.yaml \
    --env-file .env.production \
    up -d
}
```

## Anti-patterns

- Compose files at repo root in a project with 4+ modes — clutter
- Mixing service config files into `docker/` — they belong in `infra/<service>/`
- Hardcoding absolute paths in compose — use `${DATA_DIR}` or relative paths
- Different conventions per service in the same repo — pick one location pattern and stick to it
