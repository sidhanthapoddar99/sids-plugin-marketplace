# L1 — Ecosystem: across repos

The level above any single repo: how many repos exist, where the boundaries sit, what each repo is *for*, and how they share. Binds rarely — at product inception and at repo-split moments — but every L2 bootstrap inherits its answers, so settle (or explicitly note) them first. This is the **index of L1 decisions**: each decision names its owner file; the normative rule, its variants, and its audit check live there.

## Decisions owned here

| Decision | Owner file (don't restate) |
|---|---|
| One repo or several (mono vs poly) | `references/1-ecosystem/repo-boundaries.md` |
| Does a component deserve its own repo | `references/1-ecosystem/repo-boundaries.md` |
| Deployed vs distributed (the first cut) | `references/1-ecosystem/repo-boundaries.md` |
| Escalation between the above (repo-split, aggregator, Layout-06 reframe) | `references/1-ecosystem/repo-boundaries.md` |
| Docs placement (in-repo `docs/` vs separate docs repo) + docs-plugin handoff | `references/1-ecosystem/docs-placement.md` |
| How repos share code (publish > pin > vendor) | `references/1-ecosystem/cross-repo-contracts.md` |
| Aggregator repo + merged `.env.example` sync | `references/1-ecosystem/cross-repo-contracts.md` |
| Cross-repo contracts (image registry/semver, no-shared-tables) | `references/1-ecosystem/cross-repo-contracts.md` |

## Invariants

- Every repo has exactly **one role** in the ecosystem, stated in one sentence.
- Every cross-repo dependency is **pinned and mechanical** (version, ref, or sync script) — never "clone these side by side and hope".
- One product = one docs home.
- Two repos never share database tables outside a single-owner schema contract — cross-repo reads are API calls.

## What gets recorded, and where

L1 has no single config file — it's recorded redundantly where agents will actually see it:

- **Each repo's CLAUDE.md** states the repo's role and its siblings ("this repo is the deploy aggregator for `<x>`, `<y>`"; "the frontend consumes `@org/sdk` published from `<z>`").
- The **aggregator repo** (when one exists) holds the full ecosystem map.
- Sibling-repo questions are in the **always-ask list** — they can never be inferred from inside one repo (`references/01_question-flow.md`).

## Hands down to L2

Each repo enters its L2 bootstrap (`references/2-repo/00_index.md`) knowing: its role (product / service / aggregator / docs / published package), which siblings it must coordinate with and via which contract, and whether it's deployed or distributed. An L2 bootstrap that starts without these answers asks them first.

## Audit at this level

- A repo whose CLAUDE.md doesn't state its role/siblings when siblings exist = finding.
- Cross-repo sharing via unpinned sibling paths = red finding (owned by `cross-repo-contracts.md`).
- Two repos writing the same database tables = red finding (owned by `cross-repo-contracts.md`).
- Product docs duplicated across repos, or a docs site with no clear home = finding (owned by `docs-placement.md`).
- A folder that has grown external consumers or its own release cadence and hasn't been re-evaluated for repo-split = finding, the L2→L1 escalation trigger (owned by `repo-boundaries.md`).

## See also

- `references/00_altitude-model.md` — levels, principles, master tripwire table, ownership table
- `references/02_decision-tree.md` — the L2 layout picker (step 1 is the L1 deployed-vs-distributed cut, owned by `repo-boundaries.md`)
