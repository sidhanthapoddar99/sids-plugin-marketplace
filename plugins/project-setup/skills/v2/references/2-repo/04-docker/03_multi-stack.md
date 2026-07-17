# Multi-stack composition — several repos, one shared docker network

Everything else in these docs assumes **one repo = one compose stack = one private network**. This page covers the exception: several repos (each with its own `docker/` + `ctl`), whose stacks cooperate at runtime over **one shared docker network** — e.g. a chain repo + a backend repo + a frontend repo, where the frontend's nginx proxies to the backend's container by DNS name.

Each repo keeps its own compose tree, `ctl`, and `.env` exactly as `00_docker-overview.md` describes. What changes is the network, the naming, and the wiring between stacks.

## One owner, many joiners

Exactly **one** stack declares and creates the shared network; every other stack joins it as `external`:

```yaml
# owner stack (the one at the bottom of the dependency chain) — creates the network
networks:
  myapp-net: { driver: bridge, name: myapp-net }
```

```yaml
# every joining stack — same name, external
networks:
  myapp-net: { external: true, name: myapp-net }
```

Two stacks both "owning" the network is an error — you get a name fight or duplicate networks depending on creation order. Pick the owner deliberately (usually the stack at the bottom of the dependency chain) and record it in each repo's README. (Same mechanism as the `traefik` modifier's `traefik-proxy: { external: true }` — here applied to the whole inter-stack fabric, not just the edge.)

## Project-prefixed service names

On a shared network, **service names are shared DNS**. The single-stack advice ("call the service `postgres`, it resolves inside the private network") is correct *only single-stack*: if two joined stacks each have a `postgres`, cross-stack DNS resolution becomes a lottery — which container answers depends on startup order.

Joining stacks use **project-unique service names**: `myapp-postgres`, `myapp-backend`, not `postgres`, `backend`.

This renames ripple through everything that references service names — rename them together:

- `DATA_SVCS` in `_lib.sh` (`DATA_SVCS="myapp-postgres redis"` → health checks, `ctl dev` bring-up)
- modifier files (`compose.m.expose_data.yaml` publishes by service name)
- `container/shell.sh` smart targets — consider accepting short aliases so muscle memory survives: `postgres|myapp-postgres)` in its case statement

## Deploy order is a documented contract

`depends_on` cannot cross stacks — compose has no view into another project's services. The bring-up order is therefore a **convention you must write down**, in each repo's README and `ctl` help:

1. the network owner's stack (creates the network — joiners fail with *"network … not found"* until it exists)
2. upstream stacks (data, chain, backends)
3. edge stacks (frontends / reverse proxies)

Tear-down runs in reverse; the owner's `down` removes the network only after all joiners have left it.

## Cross-stack env wiring

- **Service-to-service URLs** (docker DNS paths like `http://myapp-backend:8000`) travel as env vars set in compose `environment:` — that's tier 3, wins over any `.env` file (see `references/2-repo/03-env-config/00_env-precedence.md`).
- **Credentials / secrets** are never set in compose `environment:` — always from each repo's root `.env` via `${VAR}` interpolation, identical mechanism dev and prod.

## Dev must not depend on the shared network

Standalone dev configs (`compose.data.yaml` and friends) keep their **own bridge network**, not the shared one — the dev loop (`ctl dev`) must work with every other stack down. Only the configs that actually talk cross-stack (typically `prod` / the full stack) join the shared network.

## nginx across stacks: resolve at request time, not startup

With a literal `proxy_pass http://<service>:<port>` (or an `upstream` block), nginx resolves the hostname **once at startup**. In-stack this never bites — `depends_on` guarantees the upstream container exists. Cross-stack, if the upstream stack is down when nginx starts, nginx exits with `[emerg] host not found in upstream` and crash-loops.

**Debugging tell:** the crash-looping container shows a perpetually-young `Up N seconds` in `docker ps` — the restart policy keeps resetting the clock. Check `docker inspect -f '{{.RestartCount}}' <container>` and `docker logs <container> 2>&1 | grep emerg`.

The canonical fix — hold the upstream in a **variable**, which forces per-request resolution via docker's embedded DNS:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;        # docker's embedded DNS
set $backend_upstream ${BACKEND_UPSTREAM};      # envsubst-rendered origin, held in a VARIABLE

location ^~ /api/ {
    proxy_pass $backend_upstream$request_uri;   # variable ⇒ per-request resolution
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    # …
}
```

Two gotchas to know going in:

- **(a) Variable `proxy_pass` skips startup resolution** — that's the point. nginx boots cleanly, serves static, returns 502 on proxied paths while the upstream stack is down, and recovers automatically when it appears. A 502 on `/api/*` with static content fine is the expected "upstream stack not up yet" signature, not an nginx misconfiguration.
- **(b) Variable `proxy_pass` does not auto-append the matched URI.** A literal `proxy_pass http://backend;` forwards the request path; the variable form sends every request to `/` unless you append `$request_uri` explicitly, as above.

**envsubst pairing:** when the nginx image renders config templates with envsubst, restrict which variables it substitutes, or it eats nginx's own runtime vars (`$host`, `$request_uri`, `$backend_upstream`):

```dockerfile
ENV NGINX_ENVSUBST_FILTER=BACKEND_UPSTREAM
```

`BACKEND_UPSTREAM` (e.g. `http://myapp-backend:8000`) is a service-to-service URL — set it in compose `environment:`, per the wiring rules above.

## Anti-patterns

- Two stacks both declaring (owning) the shared network — one owner, everyone else `external: true`.
- Generic service names (`postgres`, `backend`) on a shared network — project-prefix them; generic names are single-stack advice.
- A literal `proxy_pass` / `upstream` block pointing at another stack's service — startup-time resolution crash-loops when that stack is down; use the resolver + variable form.
- `depends_on` reaching for a service in another stack — it can't; document the bring-up order instead.
- Dev configs joining the shared network — the dev loop must survive every other stack being down.
- Secrets in compose `environment:` to "wire stacks together" — only DNS paths travel that way; secrets stay in each repo's `.env`.

## See also

- `00_docker-overview.md` — the single-stack 2-axis model this page extends; the `traefik` modifier (the same `external: true` join, edge-only)
- `references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md` — escalations *within* one repo (profiles, `docker/<mode>/` trees); this page is the *across-repos* analogue
- `references/2-repo/03-env-config/00_env-precedence.md` — why compose `environment:` (tier 3) carries URLs and `.env` carries secrets
- `references/2-repo/04-docker/04_proxy-and-exposure.md` — the in-stack nginx baseline this page's resolver pattern extends
