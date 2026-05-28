# `docker/` structure — profiles, configs, and `.m.` modifiers

All compose files live under `docker/`. Root keeps at most `.env` / `.env.example`. Three axes shape the stack, each a distinct compose mechanism — getting the split right is the point of this doc:

- **Profiles** — *which services run.* Tagged in `compose.yaml` with `profiles:`, activated with `--profile`. The everyday axis: `ctl up`, `ctl up app`. **~90% of variation is here.**
- **Configs** — *a full alternate deployment config* (rare). File `compose.<name>.yaml`, applied `--config=<name>`. Today there's one: `prod`.
- **Modifiers** — *small cross-cutting overlays* layered on anything. File `compose.m.<name>.yaml` (the **`.m.`** marks it a modifier at a glance), applied `--<modifier>`. Today: `expose`, `traefik`, `no-ports`.

Why profiles carry most of the load **here specifically**: the default dev loop is `ctl dev` = apps on the **host** (uvicorn `--reload`, `bun dev`), only the data core in containers. Source is never bind-mounted; docker is for prod-like environments, not dev. So the app *containers* are only ever prod-shaped — the dev↔prod *config* difference that would force overlays mostly evaporates, and "which subset runs" (a profile) is what's left.

## Folder layout (Layout 02)

```
docker/
├── compose.yaml            # profiled base: data core (no profile) + [app] + [edge]; NO host ports
├── compose.prod.yaml       # CONFIG    (--config=prod):  image tags, resource limits, .env.production
├── compose.m.expose.yaml   # MODIFIER  (--expose):       publish host ports
├── compose.m.traefik.yaml  # MODIFIER  (--traefik):      join external traefik-proxy net + labels
└── compose.m.no-ports.yaml # MODIFIER  (--no-ports):     strip host ports (rarely needed; base is already port-less)
```

Base + config = `compose.<name>.yaml`; modifiers carry the **`.m.`** infix so you can tell them apart from configs without opening them. A single app (Layout 01) often needs only `compose.yaml`. ML (Layout 04) usually needs none. For multi-mode `docker/<mode>/` trees driven by a binary, see `complex-setups.md` (Layout 05).

### Path discipline

`docker compose` resolves paths relative to the **first `-f` file**, so with `-f docker/compose.yaml` everything is relative to `docker/`:

| Need | In the compose file |
|---|---|
| Build a service | `build: ../apps/<service>` (context one level up) |
| Bind a data dir | `${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data` — `${DATA_DIR}` from `.env`, fallback `../data` |
| Reference infra config | `../infra/<service>/<file>:/container/path:ro` |

Init scripts, nginx confs, certs go **adjacent to the service** in `infra/<service>/`, never in `docker/`. See `docker-details.md`.

## Profiles = service selection (the everyday axis)

Tag services in `compose.yaml`. Convention: the **data layer carries no profile** (always-on core), application services are **opt-in**.

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

`ctl up [profile…]` maps positional args to `--profile`. Bare `ctl up` starts only the no-profile core — the data layer `ctl dev` depends on. (Add a `full` profile on each service if you want a one-word "everything".)

> A `depends_on` target is pulled in even if its profile is inactive (compose v2). Don't lean on that for the data core — give it no profile so it's unconditional.

## Configs vs modifiers = the two overlay kinds

A profile only toggles whether a service's **one definition** runs — it can't give `backend` a different command/image/limits. Overlays do that, and they come in two flavours:

**Config (`--config=<name>` → `compose.<name>.yaml`)** — a whole alternate deployment config. `prod` is the example: registry image tags (`build: !reset null`), `deploy.resources.limits`, restart policy, often a one-shot `migrate` service. **`--config=prod` also switches `--env-file` to `.env.production`.** You pick *at most one* config.

**Modifier (`--<name>` → `compose.m.<name>.yaml`)** — a small cross-cutting tweak you layer freely on top: `--expose` (host ports), `--traefik` (edge labels/network), `--no-ports`. Modifiers stack.

```
ctl up app --expose                     # apps + host ports
ctl up app edge --config=prod --traefik # production config behind Traefik
```

When does dev genuinely differ from prod enough to need the `prod` *config* (not just a modifier)? Only the rows profiles can't reach:

| Difference | Handled by |
|---|---|
| Which services / optional extras | **profile** |
| Host ports on/off | **`--expose` modifier** (don't add it for prod) |
| `build:` vs `image:` tag, resource limits, `replicas` | **`--config=prod`** |
| External Traefik edge | **`--traefik` modifier** |

## `ctl` handles the flags

The user never types `-f`. `ctl` assembles profiles + config + modifiers + env-file and **echoes the composed command** so the active set is never hidden:

```
ctl up app edge --config=prod --traefik
▸ docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml \
    --profile app --profile edge --env-file .env.production up -d
```

`ctl up --help` auto-discovers both lists: configs are `compose.<name>.yaml`, modifiers are `compose.m.<name>.yaml`. Raw `docker compose -f docker/compose.yaml --profile app up` always remains available. See `script-usage.md`.

## Example: the prod config and the traefik modifier

```yaml
# docker/compose.prod.yaml — CONFIG: prod hardening
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
# docker/compose.m.traefik.yaml — MODIFIER: external Traefik edge
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

- Using profiles to swap dev↔prod **config** — profiles select services, they don't redefine them. Use the `prod` config.
- Faking a service subset by `!reset`-ing services out of an overlay — use a profile.
- A modifier without the `.m.` infix (or a config *with* it) — the marker is the only way `ctl` and a reader tell them apart.
- Host ports in the `compose.yaml` base — base is internal-only; expose with `--expose` (`ctl dev` does it for the data core automatically).
- Splitting compose by **concern** (`compose.frontend.yaml`) — split by profile / config / modifier, never by service.
- Auto-loaded `compose.override.yaml` as a hidden dev variant — the echoed `-f`/`--profile` line is the contract.
- A `prod` config that only swaps image tags but leaves `--reload` and no limits — see the production references.

## See also

- `script-usage.md` — `ctl up [profile] [--config] [--modifier]` dispatch + auto-discovery (`script-overview.md` for the model)
- `docker-details.md` — bind-mounts + the `data/` layout (nested pgdata trick), internal-vs-host ports (`${VAR}` for host ports), YAML anchors
- `complex-setups.md` — `docker/<mode>/` trees + Go-CLI orchestrator (Layout 05)
- `references/architecture/production/app-server-and-workers.md` — what the `prod` config carries
