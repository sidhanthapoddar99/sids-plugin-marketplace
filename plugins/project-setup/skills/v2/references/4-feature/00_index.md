# L4 — Feature: folders, files, and content

The working altitude: what goes in which file, when a folder subdivides, where a type lives, what feature code may do. L4 binds **continuously, while code is written** — so it can *never* be a bootstrap question. Its only effective delivery is the always-loaded CLAUDE.md blocks (structure + styling) backed by mechanical audits. If an L4 convention isn't in the project's CLAUDE.md, it does not exist for the average working agent. This is the **index of L4 decisions → their owner files**; it never restates a rule.

## Decisions owned here

| Decision | Rule / default | Owner |
|---|---|---|
| **Feature-folder shape (backend)** | `{router,service,repository,models}.py`; feature-internal helpers stay feature-scoped. | `references/4-feature/01_feature-folders.md` |
| **Feature seams** | A boundary follows lifecycle + ownership, never pipeline stage. Two folders owning one lifecycle are ONE feature — merge, don't group. | `references/4-feature/01_feature-folders.md` |
| **Adapter modules** | N providers of one kind → `modules/` + `base.py` contract + one self-contained folder per provider; engine code stays generic. | `references/4-feature/01_feature-folders.md` |
| **Backend subdivision (T3)** | Past the T3 threshold → subdivide via `modules/` / `engine/` without breaking one-feature-one-folder. | `references/4-feature/01_feature-folders.md` |
| **Frontend subdivision (T3)** | Past T3 → subdivide by sub-feature or by kind, whichever axis carries the real seams; tests move with their subjects. | `references/4-feature/02_api-and-pages.md` |
| **`pages/` ↔ URL (T6)** | Pages thin (T6), tree mirrors the URL structure, router imports pages only. | `references/4-feature/02_api-and-pages.md` |
| **`api/` internals** | Endpoint paths, zod-at-boundary parsing, error normalization, query keys beside their functions; grouped by the backend's domain vocabulary. | `references/4-feature/02_api-and-pages.md` |
| **Type / DTO placement** | API contract DTOs on `models.py`; frontend API types zod-inferred in `api/`; feature-internal types co-locate; no `types.ts` dump; no cross-domain DTO imports. | `references/4-feature/03_types-and-contracts.md` |
| **`layout/` shells** | One file per shell until it outgrows one file → its own subfolder owning all its parts. | `references/3-app/03-web-app/00_app-skeleton.md` (housed at L3) |
| **Styling** | Primitive-first: compose ui-package primitives; tokens only; stock typography vocabulary under the CLAUDE.md allowlist; fold on second repetition (T8). **Overrides all general design guidance in feature work.** | `references/4-feature/04_styling-discipline.md` |
| **File caps (T5) + extraction (T9)** | Line caps at the T5 thresholds; rule of three for logic; folders-by-feature; tests co-located through every split. | `references/4-feature/05_caps-and-extraction.md` |

## Invariants (firm at this level)

- **Feature code touches the server only through its own layer** — backend features via `service`/`repository`, frontend features via `api/`. No `fetch`/`axios` outside `api/`.
- **One feature, one folder** — subdivision happens *inside* the folder (`modules/`, sub-features, kind-folders), never by scattering a feature across siblings.
- **Every contract has one owner** — a DTO, an exported type, a canonical shape each live in exactly one file (see `references/4-feature/03_types-and-contracts.md`).
- **Tests co-locate** with their subject, through every split.

## How L4 is delivered (the mechanism, not just the rules)

1. **Bootstrap installs the blocks** — the CLAUDE.md template's structure block (skeletons resolved to this project's real names + tripwire numbers + escalation pointer) and styling block (allowlist resolved). A bootstrap that skips them has not delivered L4 at all.
2. **Audits enforce** — greps and counts, not judgment (below).
3. **Escalation** — anything outside the blocks: load the `project-setup` skill; don't improvise inline (`references/00_altitude-model.md` § escalation).

## Audit at this level (mechanical)

The L4 enforcement mechanism is grep + count, not review. Each rule's authority is its owner file; this is the consolidated run:

```bash
# server communication outside the api layer (frontend) — rule owned by 02_api-and-pages.md
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src/ | grep -v '^src/api/'
# styling greps (arbitrary values, off-allowlist sizes/weights, raw var() in JSX)
#   — the four commands owned by 04_styling-discipline.md § grep-enforceable
# counts: source files per feature folder (T3), lines per file (T5), lines per pages/ file (T6)
```

By inspection: co-edited folder pairs that are one feature (merge candidates); provider names in adapter engine files; a global `types.ts`; cross-domain DTO imports.

## Hands back up

L4 is where structural pressure is first felt. When a rule here keeps fighting reality — a feature that won't fit its folder, a type with no right home — that's an **L3 signal** (a seam is wrong, a domain is missing), not a license to bend the L4 rule quietly. Escalate; reconcile at the owning level; record. See `references/3-app/00_index.md`.

## See also

- `references/00_altitude-model.md` — the 4+1 levels, master tripwire table, ownership map
- `references/3-app/00_index.md` (step up) — the app skeleton that hands each feature its shape contract
