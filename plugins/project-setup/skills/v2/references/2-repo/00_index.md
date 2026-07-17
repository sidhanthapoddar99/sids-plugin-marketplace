# L2 — Repo: one repository's shape

Everything that decides what a repo looks like from its root: layout, how apps group, the runtime triad, config flow, deployment. Binds at bootstrap; recorded in the tree itself plus the CLAUDE.md repo block. Inherits its role from L1; hands each app a named slot. This index maps **L2 decisions → their owner files**; it never restates a rule.

## Decisions owned here

| Decision | Rule / default | Owner |
|---|---|---|
| **Layout** | Pick from the six via the decision tree (deployed-vs-distributed first, then count/kind). | `references/02_decision-tree.md`, `references/2-repo/01-layouts/` (layouts 01–06) |
| **Grouping topology** | flat `apps/` (default) / plane-grouped (`apps/server/` + `apps/client/`) / hybrid; where the JS workspace roots; where packages sit. Tripwire T1; ask when both fit; record the pick. | `references/2-repo/01-layouts/00_grouping-topology.md` |
| **Frontend↔backend relationship** | core backend (default) vs BFF vs no-backend — names the contract gravity; ask at bootstrap. | `references/2-repo/01-layouts/02_multi-app-monorepo.md` § core vs BFF |
| **Two-plane split** | Separate admin/user backends only on security-posture grounds (identity namespace, exposure, cadence); then migrations move to a neutral `apps/db`. | `references/3-app/02-backend/02_two-plane-split.md` |
| **Root contract** | Root = index, not runtime: no loose code, orchestration-only root manifest, single-package containment + recorded exceptions. Workspace rooting is owned by grouping-topology. | `references/2-repo/02-root-hygiene/00_root-and-hygiene.md` |
| **Runtime triad** | mise (version contract) + one `ctl` (single entrypoint, conformance floor) + profile-less compose in `docker/` (base + standalone configs + `.m.` modifiers). | `references/2-repo/06-runtime-environment/00_runtime-triad.md` ★, `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`, `references/2-repo/04-docker/00_docker-overview.md` |
| **Env + config flow** | Root `.env` (shared) → per-service `config.yaml` via `${VAR}`; frontend env isolated (`VITE_*`); secrets matrix per environment. | `references/2-repo/03-env-config/` (all four) |
| **Hygiene** | Curated per-ecosystem `.gitignore` (secrets, `data/**` + `.gitkeep` negation, ecosystem artifacts); `.vscode/` and `.claude/` selectively committed. | `references/2-repo/02-root-hygiene/00_root-and-hygiene.md` § gitignore |
| **DB engines (provisioning)** | Pick the right floor (SQLite vs Postgres; in-process vs Redis); `infra/` = committed config, `data/` = gitignored state. Engine choice is repo-level; per-app usage is L3. | `references/3-app/04-database/00_provisioning.md` |
| **Deployment** | Reverse-proxy posture (Traefik modifier / nginx edge / raw expose tiers), prod config (`ctl up prod`), readiness checklist. Worker model is L3. | `references/2-repo/04-docker/04_proxy-and-exposure.md`, `references/2-repo/04-docker/05_production-readiness.md` |
| **ML vs app fork** | ML projects take Layout 04 (uvenv + `requirements.txt`, no compose) and the cloud-orchestration set. Always asked, never inferred from `.py`. | `references/2-repo/01-layouts/04_ml-project.md`, `references/2-repo/07-ml-orchestration/00_custom-orchestrator.md` |
| **Platform surfaces (non-web)** | Web is the default; mobile / desktop / PWA are additional surfaces asked at bootstrap (Q16) but **owned at L3** as app kinds — native/desktop apps live under `apps/` and share `packages/`; a PWA is the web frontend plus a manifest + service worker, not a separate app. | `references/3-app/07-mobile-app/00_mobile-app.md`, `references/3-app/06-desktop-app/00_desktop-app.md`, `references/3-app/03-web-app/02_pwa.md` |
| **Docs slot** | Scaffold the `docs/` slot per the L1 placement decision; hand off to the docs plugin. | `references/1-ecosystem/docs-placement.md` |
| **Tooling** | lefthook (default yes for multi-app repos), VS Code debug configs, CI templates. | `references/2-repo/05-ctl-scripts-tooling/` |
| **Contracts** | README documents the three startup paths; every service ships its own README; CLAUDE.md carries the repo block. | `references/2-repo/02-root-hygiene/01_readme-three-paths.md`, `references/handoffs/claude-folder.md` |

## Invariants (firm at this level)

- **Clean root** — config + README + folders + `ctl`; nothing else (`references/2-repo/02-root-hygiene/00_root-and-hygiene.md`).
- **One `ctl` per repo**, at or above the conformance floor — adapt by deletion, never by collapse (`references/2-repo/05-ctl-scripts-tooling/00_script-overview.md` § conformance floor).
- **Profile-less compose** in `docker/`; production is `ctl up prod`, never a separate verb.
- **Env split** — backend secrets never reach a frontend env scope.
- **mise is the version contract**; `ctl` is callable bare via its PATH.
- **Ecosystem-typed code layout** — Python service → `app/`, frontend → `src/`, package → `src/<pkg>/`; nesting follows app count (one → `./<name>/`, several → `apps/<name>/`).

## Named variants (choices, not drift — record each in CLAUDE.md)

topology (flat / plane-grouped / hybrid) · workspace rooting (repo root / group folder) · backend role (core / BFF) · two-plane split (yes/no) · DB engines · proxy posture (traefik / nginx-edge / raw expose) · root-manifest exception (if taken, with reason).

## Tripwires at this level

T1 (plane grouping) — owned by `references/2-repo/01-layouts/00_grouping-topology.md`; T7 (`ctl` → binary), T10 (root manifest deps) — see the master table in `references/00_altitude-model.md`. Plus the escalation triggers in `references/02_decision-tree.md` (Layout 01→02 on the second app; 02→03 on real independent cadences).

## Hands down to L3

Each app receives: its slot and name (`apps/<group?>/<name>/`), its ecosystem layout (`app/` vs `src/`), its config surface (`config.yaml` + which root `.env` vars), its Dockerfile obligation, and — for backends sharing a DB — the schema-ownership rule it must honor. See `references/3-app/00_index.md`.

## Audit at this level

- Tree vs the **recorded** layout + variants (a plane-grouped repo with a recorded choice is conformant; an unrecorded exotic tree is the finding).
- Root contract: loose code, root-manifest runtime deps, polyglot repo with root-rooted workspace, missing/incomplete `.gitignore`.
- `ctl` conformance floor mechanically (single-file `ctl` = red).
- Compose: profiles present without a recorded complex-setup escalation; ports in base; missing prod config.
- Env: tracked `.env` (red), secrets in a frontend scope (red), `config.yaml` at root.
- README three paths present; CLAUDE.md repo block present (missing = red — nothing else holds conventions for future agents).

## See also

- `references/00_altitude-model.md` — the 4+1 levels, master tripwire table, ownership table
- `references/02_decision-tree.md` — the L2 layout picker
- `references/2-repo/01-layouts/00_grouping-topology.md` — topology, workspace rooting, package scope
- `references/1-ecosystem/00_charter.md` (step up) · `references/3-app/00_index.md` (step down)
