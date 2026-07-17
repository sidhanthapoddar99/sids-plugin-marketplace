# Docker details — bind-mounts, data dirs, ports, anchors

The lower-level docker conventions `references/2-repo/04-docker/00_docker-overview.md` builds on: how stateful services bind to the host (bind-mounts + the `data/` layout, including the Postgres nested-dir trick), the internal-vs-host port rule, and when to reach for YAML anchors.

## Bind-mounts, not named volumes

Default to **bind-mounting host directories** for all stateful services; named volumes are not used (the top-level `volumes:` section stays empty).

```yaml
# YES — bind-mount
services:
  postgres:
    volumes:
      - ${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data
# NO — a named `pgdata:` under a top-level volumes: block
```

**Why:** visible (`ls data/postgres/pgdata` shows the real files), backup-friendly (`rsync data/ remote:…`), migrate-friendly (copy the dir, mount the same path elsewhere), no docker-managed metadata, fewer moving parts when troubleshooting.

**Trade-offs:** the container UID must be able to write the host dir (`user:` / `init: true`, and document it); bind-mounts can be slower on Docker Desktop (acceptable — prod is Linux); you lose named-volume-only features like volume drivers (not needed).

### Folder discipline

State lives under `data/<service>/<subdir>/`; `data/` is gitignored except `.gitkeep`:

```
data/
├── postgres/.gitkeep           # parent committed; pgdata/ created at first run (nested-dir trick below)
├── redis/.gitkeep              # data/ (AOF) created at first run
├── seaweed/{master,volume,filer}/
└── meili/
```

The gitignore negation pattern that commits the structure (via `.gitkeep`) but never the data is owned by `references/2-repo/02-root-hygiene/00_root-and-hygiene.md` § `.gitignore` doctrine — fresh clones can `ctl dev` immediately.

### `${DATA_DIR}` override

Compose uses `${DATA_DIR:-../data}` (default in-repo — relative to `docker/`, per the path discipline in `references/2-repo/04-docker/00_docker-overview.md`). Override via env: prod `DATA_DIR=/srv/my-app/data` (`.env.production`); faster disk `DATA_DIR=/mnt/ssd/my-app` (`.env.local`); tmpfs `DATA_DIR=/tmp/my-app` (CI).

Break the rule only for: enormous ephemeral data (compile caches → a named volume, document it), or a volume shared across stacks (external bind — default to transparency).

**Anti-patterns:** mixing bind + named volume for one service; bind-mounting a single file when a dir would do (Linux gotchas); forgetting `.gitkeep` so the dir is absent on fresh clones (compose fails cryptically); letting `data/` get committed (blobs in git history are forever).

## The nested data-dir trick

Postgres refuses to `initdb` into a non-empty directory, so mounting `data/postgres/` with a committed `.gitkeep` inside it fails:

```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
```

But you want `.gitkeep` so the directory survives a fresh clone (git doesn't track empty dirs). **The fix: bind-mount a NESTED dir** and keep `.gitkeep` one level up:

```
data/postgres/
└── .gitkeep        # commits the parent; pgdata/ is created at first run
```

```yaml
volumes:
  - ${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data   # nested — empty on first boot
```

`ctl` makes the nested dirs on first run — bake this into the dispatcher:

```bash
mkdir -p data/postgres/pgdata data/redis/data data/seaweed/{master,volume,filer}
```

This is the **canonical pattern**: commit `.gitkeep` in `data/postgres/`, let `ctl` create `pgdata/`, mount the nested path so initdb sees an empty dir. It applies to any service that initialises state on first boot — **Postgres** (initdb), **Redis** (AOF), **Meilisearch**.

**SELinux:** if the container can't write the bind-mount, append `:Z` (`…/pgdata:/var/lib/postgresql/data:Z`) — orthogonal to the empty-dir issue.

**Anti-patterns:** committing data files (only `.gitkeep`); bind-mounting `data/postgres/` directly with a `.gitkeep` inside it; dropping the bind-mount because "the wrapper handles it" (you lose backups, migrate-ability, transparency); `chmod 777 data/` to fix permissions (fix UID matching instead).

## Internal vs published ports

A container's **internal** port — what the app listens on inside the compose network — is a **fixed convention** (backend always `8000` inside, etc.). Internal ports never collide: each container has its own network namespace. Only the **published host** port (left side of `"${VAR}:8000"`) varies, via `${VAR}` from `.env`, so several stacks can coexist on one host.

```yaml
services:
  backend:
    ports:
      - "${BACKEND_PORT:-8000}:8000"     # host var (left) : internal fixed (right)
  frontend:
    environment:
      API_URL: "http://backend:8000"      # service-to-service: name + internal port, never the host port
```

| | Internal port | Published host port |
|---|---|---|
| Value | Fixed convention (`8000`) | Variable (`${BACKEND_PORT}`) |
| Seen by | Other containers (compose network) | The host machine |
| Collisions | Impossible (separate namespaces) | Possible across stacks → vary it |
| Referenced as | `http://backend:8000` | `localhost:${BACKEND_PORT}` (dev/humans only) |

In dev (apps on host) the app binds a host port directly; in containers it's the internal port + compose network. The constant internal port keeps the two modes consistent. Host ports are published by the `expose` modifiers (`compose.m.expose*.yaml`), not the base — see `references/2-repo/04-docker/00_docker-overview.md`.

**Anti-patterns:** hardcoding the published host port (collides across stacks — vary it via `${VAR}`); hardcoding `http://localhost:8000` for service-to-service calls (use `http://backend:8000` over the compose network).

## YAML anchors & `x-` extension fields

Don't reach for anchors to DRY a single port number — `${VAR}` interpolation already does that and is more idiomatic. Anchors earn their keep for **repeated multi-line blocks**: a shared `healthcheck`, `logging`, `deploy.resources` limits, a `restart` policy, a base service definition. Park the anchor in an `x-` field (compose ignores `x-` keys) and merge with `<<:`:

```yaml
x-svc-defaults: &svc-defaults
  restart: unless-stopped
  logging: { driver: json-file, options: { max-size: "10m", max-file: "3" } }
services:
  backend: { <<: *svc-defaults, build: ../apps/backend }
  worker:  { <<: *svc-defaults, build: ../apps/worker }
```

`${VAR}` substitutes **values**; anchors reuse **structure** — don't use one where the other fits. Overusing anchors turns the compose file into unreadable indirection.

## See also

- `references/2-repo/04-docker/00_docker-overview.md` — the compose model (standalone configs + `.m.` modifiers, profile-less), folder layout, path discipline
- `references/2-repo/03-env-config/01_per-service-config.md` · `references/2-repo/03-env-config/02_frontend-env-isolation.md` — the env/config side (`${VAR}` interpolation, build-time vs runtime)
- `references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md` — multi-mode `docker/<mode>/` trees (Layout 05)
