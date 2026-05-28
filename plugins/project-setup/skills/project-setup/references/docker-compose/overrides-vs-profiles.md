# Compose overrides vs profiles

Docker compose offers two mechanisms for "the same stack with variations". They're not equivalent.

## Overrides (this project's default)

Multiple `-f` files. Later files override earlier ones. Field-by-field deep merge.

```bash
docker compose -f compose.yaml -f compose.prod.yaml up
```

Pros:

- **Explicit** — you see what's loaded
- **Composable** — stack any combination
- **Independent files** — each readable in isolation
- Scales to N modes naturally

Cons:

- Verbose `-f` flags (the `ctl` dispatcher hides them)
- Requires consistent service names across files

## Profiles

Single compose file, services tagged with `profiles:`. Activate via `--profile` or `COMPOSE_PROFILES`.

```yaml
services:
  postgres:
    profiles: ["db"]
    image: postgres:16
  backend:
    profiles: ["app", "full"]
    build: ./apps/backend
```

```bash
docker compose --profile db up                # only postgres
docker compose --profile db --profile app up  # postgres + backend
```

Pros:

- Single file
- Service-level granularity (turn individual services on/off)
- Good for "which subset of services do I want today"

Cons:

- Doesn't change service **definitions** — only which services run
- Can't override env, ports, healthchecks per profile
- Confusing when stacks share services with different configs

## When to use which

| Scenario | Use |
|---|---|
| "Same services, different config per environment" (dev vs prod) | **Overrides** |
| "Same services, different network topology" (with vs without Traefik) | **Overrides** |
| "Subset of services for a specific task" (only db, only api) | **Profiles** (or a standalone `compose.database-only.yaml`) |
| "Optional services that not everyone needs" (observability, debug tools) | **Profiles** |
| "Different host port exposure" | **Overrides** |

## The hybrid this project uses

- **Overrides** for environments (`dev`, `prod`, `traefik`, `no-ports`)
- **Standalone files** for service subsets (`database-only.yaml`)
- **Profiles** rarely — only for genuinely optional services within a mode

This keeps the mental model simple: each file is a mode; combine modes with `-f`; choose your subset via standalone files when needed.

## Example: profiles for optional observability

```yaml
# compose.yaml
services:
  backend:
    build: ../apps/backend

  prometheus:
    profiles: ["obs"]
    image: prom/prometheus

  grafana:
    profiles: ["obs"]
    image: grafana/grafana
```

```bash
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml up                 # no observability
docker compose -f docker/compose.yaml -f docker/compose.dev.yaml --profile obs up   # +observability
```

Use sparingly — the more profiles, the more confusing.

## Anti-patterns

- Trying to use profiles to swap dev↔prod configs — overrides are the right tool
- Layering 5+ overrides — at some point you're better off with a separate `compose.<mode>.yaml` that has everything inline
- Mixing both heavily — pick the right tool per axis (env=overrides, optionality=profiles)
