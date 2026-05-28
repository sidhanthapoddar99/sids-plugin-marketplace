# Compose anchors + the internal-vs-exposed port rule

Two related ideas that often get conflated. The port rule is the important one; anchors are a smaller, more situational tool.

## A. Internal vs exposed ports

A container's **internal** port — what the app listens on inside the container / compose network — is a **fixed convention**. The backend always listens on `8000` inside, the frontend on its conventional port, and so on. Internal ports never collide: each container has its own network namespace.

Only the **published host** port (the left side of `"${HOST_PORT}:8000"`) needs to vary, via `${VAR}` from `.env`, so you can run several stacks on one host without collisions.

Service-to-service traffic uses the **service name + internal port** over the compose network — never the published host port:

```yaml
services:
  backend:
    # left side (host) is variable; right side (internal) is the fixed convention
    ports:
      - "${BACKEND_PORT:-8000}:8000"

  frontend:
    environment:
      # talk to backend over the compose network by service name + internal port
      API_URL: "http://backend:8000"
```

So **internal URLs are stable constants; only host-facing ports vary.** `http://backend:8000` is the same in every environment; `${BACKEND_PORT}` changes per host.

| | Internal port | Published host port |
|---|---|---|
| Value | Fixed convention (`8000`) | Variable (`${BACKEND_PORT}`) |
| Who sees it | Other containers, over compose network | The host machine |
| Collisions | Impossible (separate namespaces) | Possible across stacks — so vary it |
| Referenced as | `http://backend:8000` | `localhost:${BACKEND_PORT}` (humans/dev only) |

In **dev** (apps on host) the app binds a host port directly; in **prod** (containers) it's the internal port + compose network. The internal port being a constant is what keeps the two modes consistent — see `references/repo-setup/docker/compose-as-deployment-modes.md`.

## B. YAML anchors & `x-` extension fields

Honest framing: do **not** reach for anchors to DRY a single port number — `${VAR}` interpolation already does that and is more idiomatic. Anchors earn their keep for **repeated multi-line blocks**: a common `healthcheck`, `logging`, `deploy.resources` limits, a `restart` policy, or a shared base service definition reused across several services.

Use an `x-` extension field to hold the anchor, then merge it with `<<:`:

```yaml
x-svc-defaults: &svc-defaults
  restart: unless-stopped
  logging: { driver: json-file, options: { max-size: "10m", max-file: "3" } }

services:
  backend:
    <<: *svc-defaults
    # ...
  worker:
    <<: *svc-defaults
    # ...
```

`x-` keys are **ignored by compose**, so they're a safe place to park anchors. And note the two tools solve different problems: `${VAR}` interpolation substitutes **values**; anchors reuse **structure**. Don't use one where the other fits.

## Anti-patterns

- Anchoring a lone port number — use `${VAR}` interpolation instead
- Making the published host port a hardcoded constant — collides across stacks; vary it via `${VAR}`
- Hardcoding `http://localhost:8000` for service-to-service calls — use `http://backend:8000` over the compose network
- Overusing anchors until the compose file is unreadable indirection — anchors are for genuinely repeated blocks, not everything

## See also

- `references/repo-setup/docker/compose-as-deployment-modes.md`
- `references/repo-setup/docker/overrides-vs-profiles.md`
- `references/repo-setup/docker/docker-folder-layout.md`
- `references/repo-setup/env-and-config/yaml-var-interpolation.md`
- `references/repo-setup/env-and-config/build-time-vs-runtime.md`
