# Example 05 — polyrepo with deploy aggregator (Layout 03)

A complete, anonymized polyrepo product: three independently-released service repos plus a `-deploy` aggregator. The service repos are sketched briefly (each is internally a Layout 01/02, covered by other examples); the **aggregator is shown in full** — merged `.env.example`, image-based compose, sync script — because that repo is what Layout 03 is about. Domain here is a generic storefront product.

This is a worked instance of `references/2-repo/layouts/03_polyrepo-aggregator.md`. The *contracts* it demonstrates (env sync, image/semver, no shared tables, sharing rank) are owned by `references/1-ecosystem/cross-repo-contracts.md`; the *when-polyrepo* call by `references/1-ecosystem/repo-boundaries.md`. Nothing here is normative — see the mapping table at the end.

## Ecosystem — a directory of sibling repos (NOT one repo)

```
storefront/                            # a plain directory of sibling clones — NO root git, NO root manifest
├── storefront-api/                    # own repo — FastAPI + Postgres (Layout 02 internally)
├── storefront-workers/                # own repo — Rust background workers (Layout 01 internally)
├── storefront-web/                    # own repo — Vite/React frontend (Layout 02 internally)
├── storefront-docs/                   # own repo — docs site (owned by the docs plugin, not vendored here)
└── storefront-deploy/                 # ← THE AGGREGATOR (shown in full below)
```

Each service releases on its own cadence, has its own CI that builds + pushes an image, and owns the **subset** of env keys it consumes. No repo reads another's database tables — cross-service data access is an API call (`storefront-workers` calls `storefront-api`, never its DB).

## The three service repos (sketched)

Each is an ordinary app repo — full shape lives in the app examples. What matters here is the *seams* they expose to the aggregator: an `.env.example` subset, a `Dockerfile` whose CI pushes a tagged image, and a README that points ops at the aggregator.

```
storefront-api/                        # Layout 02 — see example 02/03 for the full internals
├── .env / .env.example                # SUBSET: only the keys this service consumes
├── apps/api/                          # flat app/ backend + domain folders
├── docker/compose.yaml                # its OWN dev/prod compose — build: from source lives HERE
├── Dockerfile                         # CI: build → test → push ${REGISTRY}/storefront-api:<sha> and :<tag>
├── ctl
└── README.md                          # dev instructions; defers deploy to storefront-deploy

storefront-workers/                    # Layout 01 — Rust workers, its own compose + Dockerfile
└── … (same seam: .env.example subset, Dockerfile → pushed image, README defers deploy)

storefront-web/                        # Layout 02 — Vite frontend
├── .env / .env.example                # only VITE_* keys (build-time, browser-safe)
└── … (Dockerfile builds a static-serving image → pushed)
```

## The aggregator, in full

```
storefront-deploy/                     # deploy plumbing ONLY — no business logic, no source, no build:
├── .env.example                       # CANONICAL merged union of every child's keys, commented by consumer
├── .env                               # filled-in production values — gitignored
├── docker-compose.yaml                # references PRE-BUILT IMAGES (image: …), NEVER build:
├── docker-compose.prod.yaml           # prod overlay — limits, restart policy, replica counts
├── ctl                                # the aggregator's OWN dispatcher — `ctl up prod` deploys
├── scripts/
│   ├── sync-env-templates.sh          # fetch each child's .env.example → assert merge == committed template
│   ├── check-env-drift.sh             # child keys ⊆ aggregator (also run in each child's CI, reversed)
│   ├── pull-images.sh                 # docker compose pull, by tag
│   ├── migrate.sh                     # run migrations via a one-shot container before restart
│   └── deploy.sh                      # pull → migrate → up -d
├── .claude/                           # empty initially
├── CLAUDE.md
└── README.md                          # THE ops runbook + full repo/role map for the product
```

### Merged `.env.example` (the canonical union)

The aggregator owns the union of every child's keys; each is commented with the consuming service. Note `storefront-workers` reaches the API over `API_BASE_URL` — it has **no** `DATABASE_URL`, because only `storefront-api` owns the schema.

```bash
# ── from storefront-api ─────────────────────────────
DATABASE_URL=            # storefront-api: Postgres DSN — api owns the schema/migrations
JWT_SECRET=              # storefront-api: signs session tokens
PAYMENTS_API_KEY=        # storefront-api: payment provider

# ── from storefront-workers ─────────────────────────
REDIS_URL=               # storefront-workers: job queue
API_BASE_URL=            # storefront-workers: calls storefront-api (no shared DB access)

# ── from storefront-web ─────────────────────────────
VITE_API_BASE_URL=       # storefront-web: browser → edge (build-time, baked into the image)

# ── deploy-only ─────────────────────────────────────
REGISTRY=                # image registry prefix, e.g. registry.example.com/acme
IMAGE_TAG=               # the semver tag every service is pinned to for THIS release
```

### Image-based compose (never `build:`)

Every service is a **pre-built image** pinned by `${IMAGE_TAG}`; the aggregator composes, it does not build. Data services are stock images with a bind-mounted volume.

```yaml
# storefront-deploy/docker-compose.yaml
name: storefront
services:
  api:
    image: ${REGISTRY}/storefront-api:${IMAGE_TAG}      # built + pushed by storefront-api CI
    env_file: .env
    depends_on: [postgres, redis]
  workers:
    image: ${REGISTRY}/storefront-workers:${IMAGE_TAG}
    env_file: .env
    depends_on: [redis, api]
  web:
    image: ${REGISTRY}/storefront-web:${IMAGE_TAG}
    depends_on: [api]
  nginx:
    image: nginx:1.27
    volumes: ["../infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"]
    ports: ["80:80", "443:443"]                         # the aggregator IS the edge in prod
    depends_on: [web, api]
  postgres:
    image: postgres:16
    volumes: ["${DATA_DIR:-./data}/postgres:/var/lib/postgresql/data"]
  redis:
    image: redis:7-alpine
```

### The env-sync script

Fetches each child's `.env.example`, merges, and fails if the committed aggregator template has drifted — forcing a review before deploy. (The contract is owned by `references/1-ecosystem/cross-repo-contracts.md`; this is the body that lands in the repo.)

```bash
# storefront-deploy/scripts/sync-env-templates.sh
set -euo pipefail
{
  for repo in ../storefront-api ../storefront-workers ../storefront-web; do
    echo "# ── from ${repo##*/} ──"
    cat "$repo/.env.example"
    echo
  done
} > .env.example.merged

diff .env.example .env.example.merged || {
  echo "Aggregator .env.example is out of sync with child repos. Review and commit."
  exit 1
}
```

Each child's CI runs the reverse assertion (`check-env-drift.sh`): *its* keys must be a subset of the aggregator's — catching a service that adds a var the aggregator doesn't yet know about.

## Deploy flow

```
child CI:                 build → test → push ${REGISTRY}/<service>:<sha> and :<tag>
storefront-deploy ctl:    ctl up prod → pull-images.sh → migrate.sh (one-shot) → up -d
```

The aggregator never builds; the child repos never deploy.

## Anti-patterns (shown by their absence)

- No `build:` anywhere in the aggregator compose — it defeats the point (see `references/2-repo/layouts/03_polyrepo-aggregator.md`).
- No shared `DATABASE_URL` across `storefront-api` and `storefront-workers` — cross-service reads go through the API; the no-shared-tables rule is owned by `references/1-ecosystem/cross-repo-contracts.md`.
- No business logic in `storefront-deploy` — it is deploy plumbing only.
- Deploy is documented once, in the aggregator README — not scattered across child READMEs.

## Which references govern each part

| Part | Owner reference |
|---|---|
| Whether to be polyrepo at all (mono-vs-poly, own-repo criteria) | `references/1-ecosystem/repo-boundaries.md` |
| Env-sync contract, image/semver contract, sharing rank, no-shared-tables | `references/1-ecosystem/cross-repo-contracts.md` |
| Aggregator repo *shape*, `scripts/` + `ctl` roles | `references/2-repo/layouts/03_polyrepo-aggregator.md` |
| The `storefront-docs` repo + handoff to the docs plugin | `references/1-ecosystem/docs-placement.md` |
| Each service repo's internal shape | `references/2-repo/layouts/01_single-app.md`, `references/2-repo/layouts/02_multi-app-monorepo.md` |
| Per-service `.env.example` subset, `VITE_*` isolation | `references/2-repo/env-and-config/env-precedence.md`, `references/2-repo/env-and-config/frontend-env-isolation.md` |
| Aggregator compose / image references, edge `nginx` | `references/2-repo/runtime/docker-overview.md`, `references/2-repo/deployment/proxy-and-exposure.md` |
| `ctl up prod` dispatcher | `references/2-repo/runtime/script-overview.md` |
| `migrate.sh` migrations-on-deploy | `references/2-repo/deployment/production-readiness.md` |
| Child READMEs deferring deploy to the aggregator | `references/2-repo/readme-three-paths.md` |

## See also

- `references/2-repo/layouts/03_polyrepo-aggregator.md` — the layout this example instantiates
- `references/5-examples/03_two-plane-monorepo.md` — the monorepo you'd step *down* to if the split isn't warranted
- `references/5-examples/00_index.md` — example ↔ layout ↔ variant map
