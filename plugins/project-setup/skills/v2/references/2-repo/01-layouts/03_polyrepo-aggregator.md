# Layout 03 — polyrepo with deploy aggregator

Owns the **shape of the aggregator repo**: the `<product>-deploy` repo that composes independently-released service repos into a running product. Each service lives in its own git repo (each internally a Layout 01 or 02); a dedicated aggregator repo owns the merged env contract and the production compose.

**When to choose polyrepo over a monorepo** (independent release cadences, separate teams, differing repo visibility, per-service OSS communities) is a mono-vs-poly boundary call — owned by `references/1-ecosystem/repo-boundaries.md`. This file assumes that call is already made and describes only the resulting repo shape.

## Ecosystem shape

```
<product>/                            # a directory of sibling repos, NOT one repo
├── <product>-backend-py/             # own repo — Layout 01 or 02 internally
│   ├── .env / .env.example           # subset — only its own keys
│   ├── apps/<svc>/
│   ├── docker/compose.yaml
│   ├── ctl
│   └── README.md
├── <product>-backend-rs/             # own repo — similar shape
│   └── …
├── <product>-frontend/               # own repo
│   └── …
├── <product>-docs/                   # own repo — see docs-placement
└── <product>-deploy/                 # ← the aggregator (this file's subject)
    ├── .env / .env.example           # canonical merged contract
    ├── docker-compose.yaml           # references PRE-BUILT IMAGES, never build:
    ├── docker-compose.prod.yaml
    ├── ctl                           # the aggregator's own dispatcher (ctl up prod deploys)
    ├── scripts/
    │   ├── sync-env-templates.sh     # fetch .env.example from each child
    │   ├── check-env-drift.sh        # union of child keys ⊆ aggregator
    │   ├── pull-images.sh
    │   └── deploy.sh
    └── README.md                     # ops runbook: how to deploy the product
```

## Aggregator repo shape

The aggregator is **deploy plumbing only** — no business logic, no source code, no `build:` directives. It holds exactly four kinds of thing:

| Part | What it is |
|---|---|
| Canonical merged `.env.example` | Union of every child repo's `.env.example` keys; comments name the consuming service |
| Production compose | `image:` references to pre-built images (`ghcr.io/<org>/backend-py:v1.2.3`), never `build:` |
| Sync/drift scripts | `sync-env-templates.sh`, `check-env-drift.sh`, `pull-images.sh`, `deploy.sh` |
| `ctl` | The aggregator's own dispatcher — `ctl up prod` pulls images, runs migrations via a one-shot container, restarts services |

The build happens in each child's CI; the aggregator only composes the resulting images. The aggregator never builds; the child repos never deploy.

## The cross-repo contracts (owned elsewhere)

The normative rules that make this shape work — env-template sync (child `.env.example` union ⊆ aggregator), the image registry / semver publishing contract, the sharing ranking (publish > pin > vendor), and the no-shared-database-tables rule between services — are cross-repo contracts, owned by `references/1-ecosystem/cross-repo-contracts.md`. The `scripts/` above are where those contracts land in this repo; the contract bodies live in that file. Don't restate them here.

Docs repo placement and the handoff protocol are owned by `references/1-ecosystem/docs-placement.md`.

## Anti-patterns (shape)

- **`build:` directives in the aggregator compose** — makes the aggregator depend on child source, defeats the purpose. Reference pre-built images only.
- **Business logic in the aggregator** — it is deploy plumbing; any code belongs in a service repo.
- **A monorepo dressed as polyrepo** — sibling repos with a single team that always releases together should be one repo (Layout 02). The polyrepo trigger is real independent cadence — see `references/1-ecosystem/repo-boundaries.md`.

## See also

- `references/1-ecosystem/repo-boundaries.md` — mono vs poly, own-repo criteria, escalation triggers (the WHEN)
- `references/1-ecosystem/cross-repo-contracts.md` — env sync, image/semver contracts, sharing ranking, no-shared-tables (the contract rules)
- `references/1-ecosystem/docs-placement.md` — the docs repo and its handoff
- `references/2-repo/01-layouts/02_multi-app-monorepo.md` — the monorepo alternative (step down)
- `references/2-repo/01-layouts/05_infra-orchestrator.md` — when orchestrating many repos becomes the main job
- `references/5-examples/05_polyrepo-aggregator.md` — worked example: three service repos + the `-deploy` aggregator
