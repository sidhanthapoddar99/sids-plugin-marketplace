# `docker/` structure — standalone configs + `.m.` modifiers (profile-less)

All compose files live under `docker/`. Root keeps at most `.env` / `.env.example`. The stack is shaped by **two axes** — getting the split right is the point of this doc:

- **Config** — *which scenario runs.* The base `compose.yaml` is the default (the whole stack). Each `compose.<name>.yaml` is a **standalone** scenario selected by name (`ctl up <name>`) that **replaces** base — a different service set (just the data layer, the prod stack). **One per run, optional.**
- **Modifiers** — *small cross-cutting overlays* layered on whichever config you chose. File `compose.m.<name>.yaml` (the **`.m.`** marks it a modifier at a glance), applied `--modifier <name>`. Stackable. Today: `expose`, `expose_data`, `expose_all`, `traefik`.

**There are no profiles.** Every service in the chosen compose file just runs — at the ≤5 services a typical repo has, you almost always want the whole set, so a second "which services" selection axis costs more than it pays. (Profiles are a rare advanced escalation for genuine multi-group service meshes — see `complex-setups.md`. Don't reach for them by default.)

Why this shape works **here specifically**: the default dev loop is `ctl dev` = apps on the **host** (uvicorn `--reload`, `bun dev`), only the data core in containers. Source is never bind-mounted; docker is for prod-like environments, not dev. So app *containers* are only ever prod-shaped — the dev↔prod *config* difference that would force overlays mostly evaporates, and "run the whole stack, or one named slice" is what's left.

## Folder layout (Layout 02)

```
docker/
├── compose.yaml                  # base: the WHOLE stack, NO profiles, NO host ports, internal net
├── compose.data.yaml             # CONFIG  (ctl up data): standalone — just postgres + redis
├── compose.prod.yaml             # CONFIG  (ctl up prod): standalone — hardened prod stack (.env.production)
├── compose.m.expose.yaml         # MODIFIER (--modifier expose):      publish nginx (the edge) only
├── compose.m.expose_data.yaml    # MODIFIER (--modifier expose_data): publish postgres + redis (ctl dev uses this)
├── compose.m.expose_all.yaml     # MODIFIER (--modifier expose_all):  publish every service (debug)
└── compose.m.traefik.yaml        # MODIFIER (--modifier traefik):     join external traefik-proxy net + labels
```

Configs are `compose.<name>.yaml`; modifiers carry the **`.m.`** infix so you can tell them apart from configs without opening them. A single app (Layout 01) often needs only `compose.yaml`. ML (Layout 04) usually needs none. For multi-mode `docker/<mode>/` trees driven by a binary, see `complex-setups.md` (Layout 05).

### Path discipline

`docker compose` resolves paths relative to the **first `-f` file**, so with `-f docker/compose.yaml` everything is relative to `docker/`:

| Need | In the compose file |
|---|---|
| Build a service | `build: ../apps/<service>` (context one level up) |
| Bind a data dir | `${DATA_DIR:-../data}/postgres/pgdata:/var/lib/postgresql/data` — `${DATA_DIR}` from `.env`, fallback `../data` |
| Reference infra config | `../infra/<service>/<file>:/container/path:ro` |

Init scripts, nginx confs, certs go **adjacent to the service** in `infra/<service>/`, never in `docker/`. See `docker-details.md`.

## Config = which scenario (standalone, replaces base)

Base `compose.yaml` declares the whole stack, no profiles — `ctl up` (bare) runs all of it. A **config is a standalone file that replaces base**: `ctl up data` runs `docker compose -f docker/compose.data.yaml up`, so *only* what that file declares comes up.

```
ctl up                  # base = the whole stack (postgres redis backend frontend nginx)
ctl up data             # just the data layer (compose.data.yaml replaces base)
ctl up prod             # the hardened prod stack (compose.prod.yaml replaces base)
```

This is how the profile-less model expresses "run a subset": instead of a `data` profile, you write a `compose.data.yaml` that *is* the data-only scenario and select it by name. The redundancy (a standalone config re-declares its services) is real but cheap for a handful of discrete scenarios, and far easier to reason about than profile combinatorics — **redundancy but simpler** is the right trade at this scale.

**Standalone vs overlay configs.** The shipped `docker-up.sh` treats a config as **standalone** (replaces base). If you'd rather a config *overlay* base (`-f base -f config`, the classic prod-as-overlay that avoids re-declaring services), that's a one-line change in `docker-up.sh` (marked `[ADAPT]` there) — `compose.prod.yaml` shows the standalone form; both are valid and the file's role is a documented per-project choice. A config named `<x>` auto-uses `.env.<x>` if present (e.g. `prod` → `.env.prod`).

## Modifiers = cross-cutting overlays (stackable)

A config picks the service *set*; a modifier layers a small cross-cutting tweak onto it. File `compose.m.<name>.yaml`, applied `--modifier <name>` (comma-list, repeatable). Modifiers stack and overlay whichever config you chose.

The shipped expose modifiers are a **tiered split** — base is port-less, so you opt into exactly the exposure you want:

| Modifier | Publishes | When |
|---|---|---|
| `expose` | nginx only (the edge) | run the whole stack locally behind the reverse proxy — the safe default |
| `expose_data` | postgres + redis | host dev reaching the containerised data core (`ctl dev` applies it automatically) |
| `expose_all` | every service | debugging — talk to a service directly, bypassing nginx |
| `traefik` | — (joins external Traefik net + labels) | production ingress behind a shared Traefik |

```
ctl up --modifier expose                 # whole stack, nginx on $NGINX_PORT
ctl up data --modifier expose_data       # just the DB, reachable from the host
ctl up prod --modifier traefik           # prod stack behind external Traefik
ctl up --modifier expose_all -y          # everything published (debug), no prompts
```

> **Why tier expose.** A single "expose everything" modifier over-publishes whenever the apps aren't gated — which, with no profiles, is always. Publishing only the edge by default keeps the reverse proxy the sole entry point (less noise, smaller attack surface); `expose_all` is the explicit opt-in when you need direct access.

## `ctl up` handles the flags — and is interactive

The user never types `-f`. `ctl up` assembles the config + modifiers + env-file, **echoes the composed command**, and (in a terminal) walks you through it:

```
ctl up                       # interactive: pick config → pick modifiers → see a plan → Run/Back/Cancel
ctl up prod --modifier traefik --nqa -y     # fully scripted (CI): no prompts, no confirm
```

Bare `ctl up` in a TTY prompts only for the axes you didn't pass, renders a **plan** (the real `docker compose config` merge — services, published ports, networks, volumes — which also validates the combo early), and prints the exact `--nqa` command that reproduces the run. `ctl up --list` tersely enumerates the discovered configs + modifiers. The non-interactive flag path is 100% intact for CI. Full mechanics, the plan screen, and the `--nqa`/`-y` split are in `script-usage.md`; the model is in `script-overview.md`.

```
ctl up prod --modifier traefik
▸ docker compose -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml up -d --build
```

`ctl up --help` / `--list` auto-discover both lists: configs are `compose.<name>.yaml` (minus base), modifiers are `compose.m.<name>.yaml`. Raw `docker compose -f docker/compose.yaml up` always remains available.

## Example: a standalone slice and the traefik modifier

```yaml
# docker/compose.data.yaml — CONFIG: the data layer alone (replaces base)
name: ${COMPOSE_PROJECT_NAME:-myapp}
services:
  postgres: { image: pgvector/pgvector:pg16, ... }
  redis:    { image: redis:7-alpine, ... }
networks:
  internal: { driver: bridge }
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

## No data core?

If the project has no database (static frontend, pure API gateway, SDK, ML repo), set `DATA_SVCS=()` in `_lib.sh` — every worker degrades gracefully, the apps become the always-on stack, and `expose` tiers shift to the app services. The exact lines to change are in `no-data-core.md` (the topology analogue of `script-alternatives.md`).

## Anti-patterns

- Reaching for profiles to express "a subset of services" — write a standalone `compose.<name>.yaml` and select it by name. Profiles are the rare multi-group-mesh escalation (`complex-setups.md`), not the default.
- A modifier without the `.m.` infix (or a config *with* it) — the marker is the only way `ctl` and a reader tell them apart.
- Host ports in the `compose.yaml` base — base is internal-only; expose with a modifier (`ctl dev` applies `expose_data` for the data core automatically).
- A single "expose everything" modifier — tier it (`expose` edge / `expose_data` / `expose_all`) so the default doesn't over-publish.
- Splitting compose by **concern** (`compose.frontend.yaml`) — a config is a whole scenario, not one service; split by scenario / modifier, never by service.
- Auto-loaded `compose.override.yaml` as a hidden dev variant — the echoed `-f` line is the contract.
- A `prod` config that only swaps image tags but leaves `--reload` and no limits — see the production references.

## See also

- `script-overview.md` — the `ctl`/`scripts` model (the 2-axis `ctl up`); `script-usage.md` — the interactive flow, plan screen, `--list`, dispatch + auto-discovery
- `no-data-core.md` — `DATA_SVCS=()` + apps-as-core: the exact lines to change for a DB-less project
- `docker-details.md` — bind-mounts + the `data/` layout (nested pgdata trick), internal-vs-host ports (`${VAR}` for host ports), YAML anchors
- `complex-setups.md` — profiles as the advanced multi-group escalation; `docker/<mode>/` trees + Go-CLI orchestrator (Layout 05)
- `references/architecture/production/app-server-and-workers.md` — what the `prod` config carries
