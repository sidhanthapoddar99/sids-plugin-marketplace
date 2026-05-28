# `docker/` structure — profiles for selection, `--config` overlays for the rest

All compose files live under `docker/`. Root keeps at most `.env` / `.env.example`. Two axes shape the stack, and they use **different compose mechanisms** — getting this split right is the whole point of this doc:

- **Profiles** — *which services run.* Tag services with `profiles:`; activate with `--profile`. The everyday axis: `ctl up data`, `ctl up app`. **~90% of variation is here.**
- **`--config` overlays** — *how a service is defined,* for the rare cases profiles structurally can't express (image vs build, resource limits, prod hardening). Extra `-f` files: `compose.<name>.yaml`.

Why profiles carry most of the load **in this project specifically**: the default dev loop is `ctl dev` = apps on the **host** (uvicorn `--reload`, `bun dev`), with only data services in containers. Source is never bind-mounted; docker is used for prod-like environments, not dev. So the app *containers* are only ever prod-shaped — the dev↔prod *config* difference that would force overlays mostly evaporates, and "which subset runs" (a profile question) is what's left.

## Folder layout (Layout 02)

```
docker/
├── compose.yaml          # base: ALL services declared, grouped by profile, NO host ports
├── compose.expose.yaml   # --config=expose  → publish host ports
├── compose.traefik.yaml  # --config=traefik → join external traefik-proxy net + labels
└── compose.prod.yaml     # --config=prod    → image tags, resource limits, .env.production
```

A single app (Layout 01) often needs only `compose.yaml`. ML (Layout 04) usually needs no compose. For the multi-mode `docker/<mode>/` tree driven by a binary, see `references/repo-setup/complex-setups/orchestrator-escalation.md` (Layout 05).

### Path discipline

`docker compose` resolves paths relative to the **first `-f` file**, so with `-f docker/compose.yaml` everything is relative to `docker/`:

| Need | In the compose file |
|---|---|
| Build a service | `build: ../apps/<service>` (context one level up) |
| Bind a data dir | `${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data` — `${DATA_DIR}` from `.env`, fallback `../data` |
| Reference infra config | `../infra/<service>/<file>:/container/path:ro` |

Init scripts, nginx confs, certs go **adjacent to the service** in `infra/<service>/`, never in `docker/`:

```
infra/
├── nginx/nginx.conf                  # baked into / mounted to the nginx container
├── postgres/init/01_extensions.sql   # mounted to /docker-entrypoint-initdb.d
└── traefik/dynamic.yaml              # reference only
```

`${DATA_DIR}` keeps the data path overridable per environment (dev `DATA_DIR=/tmp/app-data`, prod `DATA_DIR=/srv/app/data`). See `bind-mounts-not-volumes.md` and `nested-data-dir-trick.md`.

## Profiles = service selection (the primary axis)

Tag services in `compose.yaml`. The convention: the **data layer carries no profile** (it's the always-on core every `up` needs), application services are **opt-in** behind profiles.

```yaml
services:
  postgres: { image: pgvector/pgvector:pg16, ... }     # no profile → core, always up
  redis:    { image: redis:7-alpine, ... }             # no profile → core, always up
  backend:  { build: ../apps/backend,  profiles: [app] }
  frontend: { build: ../apps/frontend, profiles: [app] }
  nginx:    { image: nginx:1.27-alpine, profiles: [edge] }
```

```
ctl up              # core only: postgres + redis  (what host dev needs)
ctl up app          # + backend, frontend
ctl up app edge     # + nginx
```

`ctl up [profile…]` maps positional args to `--profile` flags. Bare `ctl up` starts only the no-profile core — which is exactly the data layer `ctl dev` depends on. `ctl up --help` lists profiles by grepping `profiles:` from `compose.yaml`. (Add a `full` profile — list it alongside `app`/`edge` on each service — if you want a one-word "everything".)

> A service that is `depends_on` a started service is pulled in even if its own profile is inactive (compose v2). Don't rely on that for the data core — give it no profile so it's unconditional.

## `--config` overlays = config variation (the escape hatch)

Profiles only toggle whether a service's **one definition** runs — they cannot give `backend` a different command/image/limits per profile. For that, layer an overlay:

```
ctl up app --config=expose            # + docker/compose.expose.yaml
ctl up app edge --config=prod --config=traefik   # prod hardening + traefik; stackable
```

`--config=<name>` adds `-f docker/compose.<name>.yaml` (after base). Stackable and order-preserving. **`--config=prod` also switches `--env-file` to `.env.production`** when present. `ctl up --help` lists configs by globbing `docker/compose.*.yaml`.

When does dev genuinely differ from prod enough to need an overlay? Only the rows profiles can't reach:

| Difference | Handled by |
|---|---|
| Which services / optional extras | **profile** |
| Host ports on/off | **`--config=expose`** (and don't add it for prod) |
| `build:` vs `image:` tag | one service def — keep both keys, `image: ${IMG:-app:dev}` |
| `--reload` vs gunicorn workers | rarely needed (dev runs on host); else **`--config=prod`** command override |
| Resource limits / `replicas` | **`--config=prod`** (or env-tuned defaults in base) |

So `compose.prod.yaml` carries the genuinely-prod config: registry image tags (`build: !reset null`), `deploy.resources.limits`, restart policy, `stop_grace_period`, often a one-shot `migrate` service. See `references/architecture/production/app-server-and-workers.md` and `production-readiness.md`.

## Profiles vs overlays — when to use which

| Scenario | Mechanism |
|---|---|
| "Which subset of services today" (data only, +app, +edge) | **profiles** |
| "Optional services not everyone needs" (observability, debug tools) | **profiles** |
| "Same services, different *config* per environment" (image tags, limits) | **`--config` overlay** |
| "Different host-port exposure" | **`--config=expose` overlay** |
| "With vs without Traefik" | **`--config=traefik` overlay** |

The trap (and the reason this matters): **don't try to swap dev↔prod *config* with profiles.** A profile can't change a service's definition, only its on/off. Conversely, don't fake service-selection with overlays that `!reset` services out — use a profile.

## `ctl` handles the flags

The user never types `-f`. `ctl` runs from repo root, assembles the profile + config + env-file flags, and **echoes the composed command before running** so the active set is never hidden:

```
ctl up app edge --config=prod --config=traefik
▸ docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml \
    --profile app --profile edge --env-file .env.production up -d
```

Raw `docker compose -f docker/compose.yaml --profile app up` always remains available for understanding. See `references/repo-setup/scripts/global-wrapper-dispatcher.md`.

## Example: the prod and traefik overlays

```yaml
# docker/compose.prod.yaml — config overlay: prod hardening
services:
  backend:
    image: ghcr.io/${GITHUB_REPOSITORY:-OWNER/REPO}/backend:${VERSION:-latest}
    build: !reset null                 # pull the tagged image, never build on the prod host
    env_file: [ ../.env.production ]
    deploy: { resources: { limits: { memory: 1G } } }
  frontend:
    image: ghcr.io/${GITHUB_REPOSITORY:-OWNER/REPO}/frontend:${VERSION:-latest}
    build: !reset null
    deploy: { resources: { limits: { memory: 256M } } }
```

```yaml
# docker/compose.traefik.yaml — config overlay: external Traefik edge
services:
  nginx:
    networks: [traefik-proxy, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${COMPOSE_PROJECT_NAME:-myapp}.rule=Host(`${DOMAIN}`)"
      - "traefik.http.services.${COMPOSE_PROJECT_NAME:-myapp}.loadbalancer.server.port=80"
networks:
  traefik-proxy: { external: true, name: traefik-proxy }
```

## Anti-patterns

- Using profiles to swap dev↔prod **config** — profiles select services, they don't redefine them. Use a `--config` overlay.
- Faking a service subset by `!reset`-ing services out of an overlay — use a profile.
- Host ports in `compose.yaml` base — base is internal-only; expose with `--config=expose`, and `ctl dev` does it for the data core automatically.
- Splitting compose by **concern** (`compose.frontend.yaml`, `compose.backend.yaml`) — split by profile (selection) or config (mode), never by service.
- Auto-loaded `compose.override.yaml` as the hidden dev variant — hides what's loaded; the echoed `-f`/`--profile` line is the contract.
- Compose files at repo root once there are 2+ — they belong in `docker/`.
- Service config files (`nginx.conf`, init SQL) inside `docker/` — they belong in `infra/<service>/`.
- Hardcoded absolute paths in compose — use `${DATA_DIR}` / relative `../`.
- A `prod` overlay that only swaps image tags but leaves `--reload` and no limits — see the production references.

## See also

- `references/repo-setup/scripts/global-wrapper-dispatcher.md` — `ctl up [profile] [--config]` dispatch + auto-discovery
- `references/repo-setup/docker/anchors-and-internal-ports.md` — internal port = fixed convention; host port = `${VAR}` (the expose overlay)
- `references/repo-setup/docker/bind-mounts-not-volumes.md` — bind-mount discipline, the `data/` layout
- `references/repo-setup/complex-setups/orchestrator-escalation.md` — `docker/<mode>/` trees + Go-CLI orchestrator (Layout 05)
- `references/architecture/production/app-server-and-workers.md` — what `compose.prod.yaml` carries
