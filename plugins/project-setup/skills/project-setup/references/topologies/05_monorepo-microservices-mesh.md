# Topology 05 — monorepo, microservices mesh

Many small backends, each with its own service boundary, in one repo. Less common than Topology 03 — usually justified only when services have **independent release cadences** but share **infra config** and **shared types**.

## When it fits

- 3+ backends, often in different languages
- Each is a real service (not a module pretending to be one)
- They communicate via HTTP / gRPC / message queue — not just shared DB
- Shared transport layer (auth, tracing) belongs in `packages/`

## Tree

```
my-platform/
├── .env / .env.example
├── .mise.toml
├── dev                             # ./dev — dispatches per-service
├── docker/
│   ├── compose.yaml                # all services
│   ├── compose.database-only.yaml
│   ├── compose.dev.yaml
│   ├── compose.prod.yaml
│   └── compose.<service>.yaml      # per-service overlay if needed
├── scripts/
├── apps/
│   ├── auth/                       # service: identity
│   ├── billing/                    # service: invoices, subscriptions
│   ├── notifications/              # service: email/sms/push
│   ├── search/                     # service: indexing + query
│   └── frontend/                   # one frontend talking to many
├── packages/                       # shared types, clients, observability
│   ├── api-clients/
│   ├── types/                      # protobuf / openapi schemas
│   └── observability/              # shared tracing + logging
├── infra/
│   ├── nginx/                      # routes /api/<svc>/* to each service
│   ├── postgres/init/
│   └── traefik/
├── data/                           # bind-mount targets
├── docs/  .claude/
└── README.md / CLAUDE.md
```

## Critical conventions

- **No shared database tables between services.** Each service owns its schema. If services need to read each other's data, that's an API call, not a JOIN.
- **One migration tool per service** (or one shared if all services are the same language).
- **Routing prefix per service** in nginx — `/api/auth/*`, `/api/billing/*`, `/api/search/*`.
- **Each service has its own `Dockerfile`.** Build context is the service folder.
- **Per-service env namespacing**: `AUTH_DATABASE_URL`, `BILLING_DATABASE_URL`, etc. Shared infra still gets the simple name (`REDIS_URL`).

## When NOT to use this topology

- "Microservice envy" — the team is small, services are tightly coupled, you'd be better off with Topology 02 or 03
- Services share a single Postgres without clear schema boundaries → that's Topology 03 with extra steps
- Different release cadences are aspirational, not real → wait until they actually exist

## Real-world reference

None of Sid's current repos are full Topology 05. `plane`'s `apps/` is the shape (multiple services in one repo) but most of its services are frontends, not backends.

## Escalation

- Services start being released independently → split into Topology 06 (polyrepo + aggregator)
- Services collapse into shared schema → consolidate to Topology 03
