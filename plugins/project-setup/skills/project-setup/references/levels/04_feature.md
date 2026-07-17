# L4 — Feature: folders, files, and content

The working altitude: what goes in which file, when a folder subdivides, where a type lives, what feature code may do. **Never bootstrap questions** — L4 binds continuously while code is written, so its only effective delivery is the always-loaded CLAUDE.md blocks (structure + styling) backed by audit checks. If an L4 convention isn't in the project's CLAUDE.md, it does not exist for the average working agent.

## Conventions owned here

| Convention | Rule | Reference |
|---|---|---|
| **Feature-folder shape (backend)** | `{router,service,repository,models}.py`; `models.py` = the API contract DTOs; feature-internal helpers stay feature-scoped. | `modularity/domain-grouping-tripwire.md` |
| **Feature boundaries** | Follow lifecycle + ownership, never pipeline stage. Two folders owning one lifecycle are one feature — merge, don't group. | `domain-grouping-tripwire.md` § feature seams |
| **Adapter modules** | N providers of one kind → `modules/` + `base.py` contract + one self-contained folder per provider; engine code stays generic. | `domain-grouping-tripwire.md` § adapter-modules |
| **Feature subdivision (frontend)** | ~10 files → subdivide by sub-feature or by kind, whichever axis carries the real seams; tests move with their subjects. | `frontend/intra-app-structure.md` § tripwire |
| **`pages/` ↔ URL** | Pages thin (~50 lines), tree mirrors the URL structure, router imports pages only. | `intra-app-structure.md` § pages vs features |
| **`api/` internals** | Endpoint paths, zod-at-boundary parsing, error normalization, query keys beside their functions; grouped by the backend's domain vocabulary. | `intra-app-structure.md` § api-layer doctrine |
| **`layout/` shells** | One file per shell until it outgrows one file → its own subfolder owning all its parts. | `intra-app-structure.md` § layout |
| **Type placement** | API types in `api/` (zod-inferred); feature-internal types co-locate; prop types in the component; store types with the store; no `types.ts` dump. | `intra-app-structure.md` § type placement |
| **Styling** | Primitive-first: compose ui-package primitives; tokens only; stock typography vocabulary under the CLAUDE.md allowlist; fold on second repetition (T8). **Overrides all general design guidance in feature work.** | `frontend/styling-discipline.md` |
| **File caps** | 500 hard / 300 soft (T5). | `modularity/file-size-caps.md` |
| **Extraction** | Rule of three for logic (T9); rule of two for styling (T8). | `modularity/extract-on-third-use.md` |
| **Tests** | Co-locate with what they test, through every split. | `modularity/folders-by-feature.md` § tests |

## How L4 is delivered (the mechanism, not just the rules)

1. **Bootstrap installs the blocks** — the CLAUDE.md template's structure block (skeletons resolved to this project's real names + tripwire numbers + escalation pointer) and styling block (allowlist resolved). A bootstrap that skips them has not delivered L4 at all.
2. **Audits enforce** — greps and counts, not judgment (below).
3. **Escalation** — anything outside the blocks: load the `project-setup` skill; don't improvise inline (`levels/00_altitude-model.md` § escalation).

## Audit at this level (mechanical)

```bash
# server communication outside the api layer (frontend)
grep -rEn --include='*.ts' --include='*.tsx' '\bfetch\(|axios' src/ | grep -v '^src/api/'
# styling-discipline greps — arbitrary values, off-allowlist sizes/weights, raw var() in JSX
#   (the four commands in styling-discipline.md § grep-enforceable)
# counts: files per feature folder (T3), lines per file (T5), lines per pages/ file (T6)
```

Plus by inspection: co-edited folder pairs that are one feature; provider names in adapter engine files; a global `types.ts`; cross-domain DTO imports.

## Hands back up

L4 is where structural pressure is first felt. When a rule here keeps fighting reality — a feature that won't fit its folder, a type with no right home — that's an L3 signal (a seam is wrong, a domain is missing), not a license to bend the L4 rule quietly. Escalate; reconcile at the owning level; record.
