# L1 — Ecosystem: decisions across repos

The level above any single repo: how many repos exist, where the boundaries sit, what each repo is *for*, and how they share. Binds rarely — at product inception and at repo-split moments — but every L2 bootstrap inherits its answers, so settle (or explicitly note) them first.

## Decisions owned here

| Decision | Rule | Reference |
|---|---|---|
| **One repo or several** | One repo until services genuinely release on independent cadences. Aspirational independence stays in the monorepo. | `references/00_decision-tree.md`, `repo-setup/layouts/02_multi-app-monorepo.md` § mesh, `layouts/03_polyrepo-with-aggregator.md` |
| **Does a component deserve its own repo** | Any ONE suffices: (a) independent release cadence, (b) external consumers beyond this product, (c) a visibility/permission boundary (open-sourcing a part, restricting another). None → it's a folder, not a repo. | `layouts/03`, `layouts/06` |
| **Deployed vs distributed** | Does a repo *run* the product or *publish a package* an external host runs? Distributed → Layout 06; the published artifact is an ecosystem-level contract. | `00_decision-tree.md` step 1, `layouts/06_embeddable-package-and-reference-host.md` |
| **Aggregator repo** | Polyrepo products get a `<product>-deploy` aggregator owning the merged `.env.example` + prod compose over built images. | `layouts/03_polyrepo-with-aggregator.md` |
| **Docs placement** | In-repo `docs/` for a single-repo product (default). A separate `<product>-docs` repo when the product spans multiple repos (one docs site can't live in all of them) or docs release/get contributed to independently. Never both; never per-repo doc fragments for one product. | `integrations/docs-integration.md` |
| **How repos share code** | Ranked: **published package** (versioned, semver) > **pinned git dependency** (ref/sha) > **vendored copy with recorded provenance**. Never path-dependencies on sibling clones for anything that ships. | `layouts/06` (publishing), `layouts/03` (contracts) |
| **Cross-repo contracts** | The allowed coupling points, each with one owner: the published-package API, the image registry + tags, the aggregator's merged `.env.example` (sync-checked by script), a shared DB schema owned by exactly one repo. **Two repos never share database tables outside a single-owner schema contract** — cross-repo reads are API calls. | `layouts/03` |

## Invariants

- Every repo has exactly **one role** in the ecosystem, stated in one sentence.
- Every cross-repo dependency is **pinned and mechanical** (version, ref, or sync script) — never "clone these side by side and hope".
- One product = one docs home.

## What gets recorded, and where

L1 has no single config file — it's recorded redundantly where agents will actually see it:

- **Each repo's CLAUDE.md** states the repo's role and its siblings ("this repo is the deploy aggregator for `<x>`, `<y>`"; "the frontend consumes `@org/sdk` published from `<z>`").
- The **aggregator repo** (when one exists) holds the full ecosystem map.
- Sibling-repo questions are in the **always-ask list** — they can never be inferred from inside one repo (`01_question-flow.md`).

## Hands down to L2

Each repo enters its L2 bootstrap knowing: its role (product / service / aggregator / docs / published package), which siblings it must coordinate with and via which contract, and whether it's deployed or distributed. An L2 bootstrap that starts without these answers asks them first.

## Audit at this level

- A repo whose CLAUDE.md doesn't state its role/siblings when siblings exist = finding.
- Cross-repo sharing via unpinned sibling paths = red finding.
- Two repos writing the same database tables = red finding.
- Product docs duplicated across repos, or a docs site with no clear home = finding.
- A folder that has grown external consumers or its own release cadence and hasn't been re-evaluated for repo-split = finding (the L2→L1 escalation trigger).
