# Examples — how to read them

Six complete, **anonymized** project trees, one per layout. Each is a worked composition: every folder and file carries a one-line purpose comment, and each example closes with a **"which references govern what"** table routing every part of the tree to its owner file. Generic product domains, no real repos, no machine paths.

Examples are **illustrations, not templates**. The normative rule for any part always lives in the reference the closing table points at — read the example to see how the rules *compose* into a real shape, then open the cited reference for the rule itself. If an example and a reference ever disagree, the reference wins (and the example is the bug).

## How each example is built

- **One layout, one variant set.** Each file fixes exactly one layout from `references/02_decision-tree.md` and commits to a named set of variants (topology, run-service vs distributable, migration owner, etc.). It does not enumerate alternatives — it shows one coherent choice end to end.
- **The tree is annotated top-down.** Root first (root is an index, not a runtime), then each service/app folder, then the skeleton inside. Comments state *purpose*, not restate rules.
- **The closing table is the index back to doctrine.** Path → what it is → governing v2 reference. This is where an auditor confirms a real repo against its recorded choices.
- **Anonymized.** Tool and service names are generic (`tablefmt`, `api-platform`, `editor`). Substitute freely; the shape is the lesson.

For the per-installation registry of the user's **real** repos (never invented), see `references/handoffs/examples-registry.md` — that is evidence; these are pedagogy.

## Example ↔ layout ↔ variants map

| Example | Layout | Variant set shown | Primary owners |
|---|---|---|---|
| `01_single-cli.md` | 01 single-app | distributable CLI · **src-layout** · minimal `ctl` (no docker verbs) · no compose / no data / no infra | `references/2-repo/01-layouts/01_single-app.md`, `references/3-app/02-backend/00_app-skeleton.md` |
| `02_canonical-1be-1fe.md` | 02 flat | FastAPI **run-service** (flat `app/`) + Vite frontend · full runtime triad (`ctl`/docker/mise) · tokens.css · Alembic · Vite-proxy↔nginx pair | `references/2-repo/01-layouts/02_multi-app-monorepo.md`, `references/3-app/03-web-app/00_app-skeleton.md`, `references/2-repo/06-runtime-environment/00_runtime-triad.md` |
| `03_two-plane-monorepo.md` | 02 plane-grouped | `apps/server/{api-platform,api-admin}` + `apps/db` neutral owner + `apps/client/{platform,admin,packages/}` **workspace-rooted at `client/`** · backend domain layer · full `src/` skeleton | `references/2-repo/01-layouts/00_grouping-topology.md`, `references/3-app/02-backend/01_domain-grouping.md`, `references/3-app/02-backend/02_two-plane-split.md` |
| `04_ml-training-project.md` | 04 ML | uvenv global env + `requirements.txt` · `configs/` · `scripts/cloud/` · checkpoints | `references/2-repo/01-layouts/04_ml-project.md`, `references/3-app/02-backend/03_ml-python-flow.md`, `references/2-repo/07-ml-orchestration/` |
| `05_polyrepo-aggregator.md` | 03 polyrepo | three independent service repos + a `-deploy` **aggregator** repo · `env.example` sync · image-based (registry) compose | `references/2-repo/01-layouts/03_polyrepo-aggregator.md`, `references/1-ecosystem/cross-repo-contracts.md` |
| `06_embeddable-package.md` | 06 embeddable | `packages/editor` product + **framework-less core** + a reference host app · single-artifact publishing · embedding seams | `references/2-repo/01-layouts/06_embeddable-package.md`, `references/3-app/05-package/02_embeddable-seams.md` |

Layouts 01/02/03/04/06 are covered by a dedicated example; **Layout 05** (Go-CLI-driven infra orchestrator) has no standalone example here — its shape lives in `references/2-repo/01-layouts/05_infra-orchestrator.md` and its escalation trigger in `references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md`.

## Reading order

Start with `01_single-cli.md` (smallest conforming repo — the runtime floor with nothing else), then `02_canonical-1be-1fe.md` (the flagship: the full canonical stack). `03` shows what `02` becomes after the plane-grouping tripwire (T1) trips. `04`/`05`/`06` are the specialised layouts.

## See also

- `references/02_decision-tree.md` — pick the layout an example demonstrates
- `references/00_altitude-model.md` — the levels + master tripwire table the closing-table owners belong to
- `references/handoffs/examples-registry.md` — the per-installation real-repo registry (never invent paths)
