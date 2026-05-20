# Topology 06 — polyrepo with deploy aggregator

Each service in its own git repo, plus a `<product>-deploy` aggregator repo that owns the merged env contract and the production compose.

## When it fits

- Independent release cadences across services (real, not hypothetical)
- Separate teams own separate services
- Services may live in private/public repos with different visibility
- Open source where each service has its own community

## Layout

```
~/projects/my-product/
├── my-product-backend-py/          # own repo
│   ├── .env / .env.example         # subset — only its own keys
│   ├── apps/<svc>/
│   ├── docker/compose.yaml
│   ├── dev
│   └── README.md
├── my-product-backend-rs/          # own repo
│   └── …                            # similar shape, Topology 01 or 02 internally
├── my-product-frontend/            # own repo
│   └── …
├── my-product-docs/                # own repo — documentation-template
└── my-product-deploy/              # ← the aggregator
    ├── .env / .env.example         # canonical merged contract
    ├── docker-compose.yaml         # references PRE-BUILT IMAGES, not build:
    ├── docker-compose.prod.yaml
    ├── deploy                      # ./deploy — aggregator wrapper
    ├── scripts/
    │   ├── sync-env-templates.sh   # fetch .env.example from each child
    │   ├── check-env-drift.sh      # union of child keys ⊆ aggregator
    │   ├── pull-images.sh
    │   └── deploy.sh
    └── README.md                   # ops runbook: how to deploy the product
```

## Aggregator responsibilities

The aggregator repo is the **deployment-time source of truth**:

1. **Canonical merged `.env.example`** — union of every child repo's `.env.example` keys. Comments name which service consumes each key.
2. **Production compose** — references pre-built images (`image: ghcr.io/me/backend-py:v1.2.3`), never `build:`. The build happens in the child repos' CI; the aggregator just composes them.
3. **`sync-env-templates.sh`** — fetches each child's `.env.example` and asserts the union. Run on update.
4. **`./deploy`** — pulls images, runs migrations (via a one-shot container), restarts services.

## Env contract sync (the hard part)

Each child repo owns its own `.env.example` — the keys it needs. The aggregator owns the union.

```bash
# aggregator/scripts/sync-env-templates.sh
for repo in ../my-product-backend-py ../my-product-backend-rs ../my-product-frontend; do
  echo "# from ${repo##*/}"
  cat "$repo/.env.example"
done > .env.example.merged

# diff against the committed aggregator template
diff .env.example .env.example.merged || {
  echo "Aggregator .env.example is out of sync with child repos. Review and commit."
  exit 1
}
```

CI in each child repo can run a similar check in reverse: "my `.env.example` keys must be a subset of the aggregator's." This catches the case where a service adds a new env var that the aggregator doesn't know about yet.

## Image flow

```
child repo CI:
  build → test → push to ghcr.io/me/<service>:<sha> and :<tag>

aggregator CI / ./deploy:
  pull ghcr.io/me/<service>:<tag> → compose up
```

The aggregator never builds. The child repos never deploy.

## Docs

A dedicated `my-product-docs/` repo — documentation-template. The aggregator's README links to it.

## When NOT to use this topology

- Single team that always releases everything together → Topology 02–04
- Services share a database with tight schema coupling → Topology 03
- Wanting "microservices" for résumé reasons → don't

## Real-world reference

None of Sid's current repos is full Topology 06. The pattern is documented from industry practice; the skill should ask carefully before recommending.

## Common mistakes to avoid

- Aggregator with `build:` directives — defeats the purpose, makes the aggregator depend on child source code
- No `sync-env-templates.sh` — envs drift, deploys break in surprising ways
- Putting business logic in the aggregator — it should be deploy plumbing only
- Documenting deploy in child READMEs — concentrate it in the aggregator
