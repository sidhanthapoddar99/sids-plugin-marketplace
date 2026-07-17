# Repo boundaries — how many repos, and where the lines fall

Owns the three L1 boundary decisions and the escalation triggers between them: **one repo or several** (mono vs poly), **does a component deserve its own repo** (own-repo criteria), and **deployed vs distributed** (does the repo run the product or publish a package). These decide what each repo *is* before any L2 layout is picked. The repo *shapes* that follow from these answers live in `references/2-repo/01-layouts/` — this file owns only the WHEN.

## Deployed vs distributed — the first cut

Ask this before layout selection. It defines what the repo is to external consumers, so it binds at L1.

> **Does this repo *run* the product, or *publish a package* an external host runs?**

| Answer | Meaning | Routes to |
|---|---|---|
| **Deployed** | You `ctl up prod` it and that's the live thing. The repo owns its own services, URLs, storage. | Layouts 01–05 (continue to `references/02_decision-tree.md` step 2) |
| **Distributed** | The deliverable is a package a *separate, external* repo installs and runs (`npm i @you/editor`, `pip install you-engine`). The repo's own app is a **reference host** — a dev harness — not the product. | Layout 06 (`references/2-repo/01-layouts/06_embeddable-package.md`) |

Distributed is orthogonal to backend/frontend count — a distributed repo can internally have a BFF, a reference frontend, and shared packages, but its *reason to exist* is the published artifact. The published package is an **ecosystem-level contract**: consumers pin a semver, so it's an L1 concern, not an internal detail.

**When distributed fits:**

- The deliverable is a **package consumers install**, not a service you deploy.
- A **different, external repo** is the real host; your repo's app is a harness.
- Language like "embeddable", "SDK", "library-as-product", "the frontend *is* the product", "mounts in someone else's app".
- The product must run inside a host it doesn't control — so it can't bake in URLs, secrets, or "where saves go".

If the repo instead *runs* the product, it's deployed (01–05), not 06. The embedding seams / IoC config API and the package's repo shape + publishing mechanics are not owned here — see `references/3-app/05-package/02_embeddable-seams.md` and `references/2-repo/01-layouts/06_embeddable-package.md`.

## One repo or several — mono vs poly

**Default: one repo.** Stay monorepo until services genuinely release on **independent cadences** — real, not hypothetical. Aspirational independence ("we might split this someday") stays in the monorepo; a multi-app monorepo (Layout 02) already gives per-app boundaries without the coordination tax of separate repos.

**When polyrepo fits (all are real signals, not résumé reasons):**

- Independent release cadences across services — actually shipped on separate schedules, not just imagined.
- Separate teams own separate services.
- Services live in repos with **different visibility** (some public, some private).
- Open source where each service has its own community.

**When NOT to split into polyrepo:**

- Single team that always releases everything together → stay Layout 02.
- Services share a database with **tight schema coupling** → stay Layout 02 (a shared schema wants one repo to own it; cross-repo table sharing is a red finding — see `references/1-ecosystem/cross-repo-contracts.md`).
- Wanting "microservices" for résumé reasons → don't.

Polyrepo products get a `<product>-deploy` aggregator repo owning the merged env contract and prod compose — the aggregator's contract responsibilities are owned by `references/1-ecosystem/cross-repo-contracts.md`; its repo *shape* by `references/2-repo/01-layouts/03_polyrepo-aggregator.md`.

## Does a component deserve its own repo — own-repo criteria

Applies to any candidate carve-out (a service, a shared library, the docs). **Any ONE of these suffices** to justify a separate repo:

1. **Independent release cadence** — it ships on its own schedule, decoupled from the rest.
2. **External consumers beyond this product** — other products or third parties depend on it.
3. **A visibility / permission boundary** — open-sourcing one part while restricting another, or a team-access boundary.

**None of the three → it's a folder, not a repo.** Prefer a folder (or a `packages/` workspace inside Layout 02) until a criterion is genuinely met. A component published as a package (criterion 2) is the distributed case above → Layout 06; docs that release/get contributed independently (criterion 1/3) is the docs-repo case → `references/1-ecosystem/docs-placement.md`.

## Escalation triggers between these decisions

Boundaries are re-openable. These L2→L1 triggers say a repo has outgrown its current boundary and must be re-evaluated:

| Trigger | Escalation |
|---|---|
| A folder grows **external consumers** or its **own release cadence** | Re-evaluate for repo-split (own-repo criteria above). Silent non-evaluation = the L1 audit finding. |
| Two repos start **sharing env vars** | Introduce a Layout 03 aggregator repo (contracts owned by `cross-repo-contracts.md`). |
| Within Layout 02, services grow **independent deploy cadences/boundaries** | The mesh end of Layout 02; if they need separate repos, escalate mono → poly (Layout 03). |
| A deployed app's **frontend or engine starts being consumed by an external repo** | Reframe deployed → distributed: the consumed part becomes a published `packages/<pkg>/` (peerDeps, `exports`), the current app demotes to a reference host (Layout 06). |

## Anti-patterns

- Splitting to polyrepo on **aspirational** independence — coordination tax with no payoff; keep it in Layout 02 until cadences are real.
- Carving a repo out with **none** of the three own-repo criteria met — a folder would have done.
- Treating a **distributed** repo's reference host (`apps/web`) as "the app" — it's a harness; the package is the product. This is the mistake that makes an embeddable package read as a headless service.
- "Microservices" for résumé reasons.

## Audit checks

- A component with external consumers / its own cadence still living as a folder, never re-evaluated for split = finding.
- A polyrepo whose services always release together and share a coupled schema = mono/poly mis-boundary finding (should be Layout 02).
- A repo whose deliverable is a published package but is structured/documented as a deployed service (or vice versa) = deployed-vs-distributed mis-classification.
- CLAUDE.md that doesn't state whether the repo is deployed or distributed when siblings/consumers exist = finding.

## See also

- `references/1-ecosystem/00_index.md` — the L1 decision index
- `references/1-ecosystem/cross-repo-contracts.md` — sharing ranking, aggregator, image/schema contracts
- `references/1-ecosystem/docs-placement.md` — the docs own-repo case + handoff
- `references/2-repo/01-layouts/03_polyrepo-aggregator.md` — the aggregator repo shape (WHEN lives here)
- `references/2-repo/01-layouts/06_embeddable-package.md` — the distributed repo shape + publishing (WHEN lives here)
- `references/3-app/05-package/02_embeddable-seams.md` — embedding seams / IoC config API
- `references/02_decision-tree.md` — step 1 is this deployed-vs-distributed cut; step 2 picks the deployed layout
