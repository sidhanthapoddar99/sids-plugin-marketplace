# Compose files = deployment modes

Multiple compose files in `docker/` are **not** split by concern (one for db, one for traefik). They're split by **deployment mode** — each file is a complete or overlay variant of how the system is deployed.

## The mode catalogue

| File | Purpose | When used |
|---|---|---|
| `compose.yaml` | Base — all services declared, **no host ports**, internal network only | Always loaded; foundation everything overlays on |
| `compose.database-only.yaml` | Only postgres + redis (and other stateful infra). No application services. | Dev mode where apps run on host with hot reload |
| `compose.dev.yaml` | Overlay — adds host port exposure to base | Local full-stack-in-containers dev |
| `compose.prod.yaml` | Overlay — production overrides (image tags, restart policies, resource limits) | Production deploy |
| `compose.traefik.yaml` | Overlay — joins external `traefik-proxy` network, adds labels | When fronted by an external Traefik |
| `compose.no-ports.yaml` | Overlay — removes host ports | Prod behind nginx-as-edge or external reverse proxy |
| `compose.local-server.yaml` | Optional — variant for a specific dev environment (e.g. WSL) | Per-machine prod-like dev |

## Composition rules

- `compose.yaml` is always the first `-f` argument. Overlays come after.
- `database-only` is **standalone** — used alone, not as an overlay.
- `dev`, `prod`, `traefik`, `no-ports` are **overlays** — applied on top of base.
- Multiple overlays can stack: `compose.yaml + compose.prod.yaml + compose.traefik.yaml`.

## Example invocations

```bash
# dev mode A — apps on host, only DBs in containers
docker compose -f docker/compose.database-only.yaml up -d

# dev mode B — everything in containers, with host ports
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up -d

# prod — behind external Traefik
docker compose \
  -f docker/compose.yaml \
  -f docker/compose.prod.yaml \
  -f docker/compose.traefik.yaml \
  --env-file .env.production \
  up -d

# prod — behind internal nginx, no host port exposure beyond what nginx serves
docker compose \
  -f docker/compose.yaml \
  -f docker/compose.prod.yaml \
  -f docker/compose.no-ports.yaml \
  --env-file .env.production \
  up -d
```

## Why this is better than `compose.override.yaml` magic

`compose.override.yaml` is auto-loaded by docker compose when present. Convenient for one-mode setups, but:

- Hides what's actually loaded ("why are these ports exposed?")
- Doesn't scale to 3+ modes
- Hard to switch modes without renaming files

Explicit `-f` arguments + named modes scale better and are auditable. The `./dev` wrapper hides the flags from day-to-day use; raw `docker compose -f docker/<file>` remains available for understanding.

## Per-mode authoring rules

- **Base (`compose.yaml`)** declares everything (services, env_file, depends_on, healthchecks, internal volumes). No host ports. Use this as the canonical reference for what runs in production.
- **Overlays** only add or override. They should be short — under 40 lines each.
- **Database-only** is a standalone copy of just the stateful services from base.
- **Networks**: traefik overlay joins an external `traefik-proxy` network; base declares only internal networks.

## Example: traefik overlay

```yaml
# docker/compose.traefik.yaml
services:
  frontend:
    networks:
      - traefik-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`${DOMAIN}`)"
      - "traefik.http.services.frontend.loadbalancer.server.port=80"

  backend:
    networks:
      - traefik-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend.rule=Host(`${DOMAIN}`) && PathPrefix(`/api`)"
      - "traefik.http.services.backend.loadbalancer.server.port=8000"

networks:
  traefik-proxy:
    external: true
    name: traefik-proxy
```

## Real-world reference

- `NeuraSutra` has the four-mode split (`docker-compose-database.yaml`, `-ports.yaml`, `-traefik.yaml`, base) at repo root. The convention here moves them into `docker/` and renames consistently (`compose.dev.yaml` is clearer than `-ports.yaml`).
- `chimere` has `docker/{singlenode,multinode,prod}/` — that's Topology 08, where modes are folders not files.

## Anti-patterns

- One huge `docker-compose.yaml` with environment-branching tricks ("if $ENV == prod then …") — not supported
- Auto-loaded `compose.override.yaml` as the only dev variant — hidden behaviour
- Splitting by concern (`compose.frontend.yaml`, `compose.backend.yaml`) — modes, not concerns
- Forgetting to test that overlays stack (`prod + traefik`) before deploying
