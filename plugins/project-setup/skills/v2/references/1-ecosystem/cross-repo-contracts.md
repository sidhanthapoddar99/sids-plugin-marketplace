# Cross-repo contracts — the allowed coupling points

Owns the L1 rules for **how separate repos in one product couple**: the ranked code-sharing options, the deploy **aggregator** repo and its contracts, the **`.env.example` sync** contract, the **image registry / semver** contract, and the **no-shared-tables** rule. Every cross-repo dependency must be *pinned and mechanical* — a version, a ref, or a sync script — never "clone these side by side and hope".

*When* to be polyrepo at all (mono-vs-poly, own-repo criteria, deployed-vs-distributed, escalation triggers) is owned by `references/1-ecosystem/repo-boundaries.md`. The aggregator repo's on-disk **shape** and the script bodies are owned by `references/2-repo/layouts/03_polyrepo-aggregator.md`. This file owns the *contracts* those shapes enforce.

## Invariant

- Every cross-repo dependency is **pinned and mechanical** (version, ref, or sync script).
- **Two repos never share database tables** outside a single-owner schema contract; cross-repo reads are API calls.
- Every allowed coupling point has **exactly one owner repo**.

## How repos share code — ranked

Prefer the highest option that works; drop down only when forced.

| Rank | Mechanism | Coupling | Use when |
|---|---|---|---|
| 1 | **Published package** (versioned, semver) | Loosest — consumers pin a version | Shared code has ≥2 consumers or an external audience. Publishing mechanics: `references/2-repo/layouts/06_embeddable-package.md`. |
| 2 | **Pinned git dependency** (ref / sha) | Medium — pinned to a commit | Not yet worth a registry release, but the code must be reused as-is. |
| 3 | **Vendored copy with recorded provenance** | Tightest acceptable — a tracked copy | Upstream can't be depended on directly; record source + ref so syncs stay mechanical. |

**Never** path-dependencies on sibling clones (`../other-repo`) for anything that ships. Sibling paths are fine only for a throwaway local spike, never committed as a build input.

## The aggregator repo

A polyrepo product gets one `<product>-deploy` aggregator: the **deployment-time source of truth**. It is deploy plumbing only — no business logic. Its contract responsibilities:

| Contract | Rule |
|---|---|
| **Merged `.env.example`** | Owns the canonical union of every child repo's `.env.example` keys, each commented with the consuming service. Sync-checked (below). |
| **Production compose over images** | References **pre-built images** (`image: …:v1.2.3`), never `build:`. Children build in their own CI; the aggregator only composes. |
| **Ecosystem map** | Its README is the product's ops runbook and the full repo/role map. |
| **Deploy dispatcher** | Its own `ctl up prod` pulls images, runs migrations (one-shot container), restarts services. |

The aggregator never builds; child repos never deploy. Repo tree, `scripts/` layout, and the `ctl` body: `references/2-repo/layouts/03_polyrepo-aggregator.md`.

## `.env.example` sync contract

Each child repo owns the subset of keys it needs; the aggregator owns the union.

- **Direction 1 (aggregator):** a sync script fetches each child's `.env.example` and asserts the aggregator's committed template equals the merge — else fail and require a review + commit.
- **Direction 2 (child CI):** each child asserts *its* keys are a **subset** of the aggregator's, catching a service that adds a var the aggregator doesn't yet know about.

The rule is the contract (union at aggregator, subset at each child, both checked mechanically). Script bodies (`sync-env-templates.sh`, `check-env-drift.sh`) live in `references/2-repo/layouts/03_polyrepo-aggregator.md`. Env precedence and per-service config within a repo: `references/2-repo/env-and-config/env-precedence.md`.

## Image registry / semver contract

```
child repo CI:      build → test → push  registry/<service>:<sha>  and  :<tag>
aggregator / ctl:   pull  registry/<service>:<tag>  →  compose up
```

- Images are pushed by **child CI only**, tagged with both an immutable `<sha>` and a moving semver `<tag>`.
- The aggregator's compose pins images by tag (or sha for reproducible deploys); it holds no `build:` directives.
- The published-image tag set is an **ecosystem-level contract**: children must not repurpose or delete tags the aggregator pins.

## No shared database tables

Two repos **never** read or write the same tables directly. Cross-repo data access is an **API call**, not a shared connection.

- A schema may be shared **only** through a single-owner schema contract: exactly one repo owns the migrations and the table definitions; others consume via that repo's API.
- Tight schema coupling between services is a signal the split was wrong — collapse to Layout 02 (single monorepo) instead of forcing a shared DB across repos.
- Engine choice and `infra/`-vs-`data/` placement: `references/2-repo/databases-provisioning.md`. Per-engine usage conventions: `references/3-app/database-usage/`.

## Audit checks

- Cross-repo sharing via **unpinned sibling paths** (`../repo` build inputs) = red finding.
- **Two repos writing the same database tables** outside a single-owner schema contract = red finding.
- Aggregator carrying **`build:` directives** or business logic = finding (it must be deploy plumbing over pre-built images).
- **No `.env.example` sync check** between children and aggregator = finding (envs drift silently, deploys break).
- A shared dependency copied by hand with **no recorded provenance / pin** = finding.

## See also

- When to go polyrepo, own-repo criteria, deployed-vs-distributed, escalation triggers: `references/1-ecosystem/repo-boundaries.md`.
- Aggregator repo shape + script bodies: `references/2-repo/layouts/03_polyrepo-aggregator.md`.
- Publishing a shared package (rank 1): `references/2-repo/layouts/06_embeddable-package.md`.
- Docs across repos (why not to vendor the docs repo): `references/1-ecosystem/docs-placement.md`.
- L1 decision index and where role/siblings get recorded: `references/1-ecosystem/00_charter.md`.
