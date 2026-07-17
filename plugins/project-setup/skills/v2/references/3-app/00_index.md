# L3 — App: inside one app or package

The internal structure of each runnable app and each workspace package: its skeleton, how features group, where shared code and contracts live, how its data layer is owned and served. Binds when the app is created — mostly derived from L2's decisions plus a few per-app questions — and is recorded in the CLAUDE.md structure block. Inherits its slot from L2; hands folder-level contracts down to L4. This is the **index of L3 decisions → their owner files**; it never restates a rule.

## Decisions owned here

| Decision | Rule / default | Owner |
|---|---|---|
| **Every-app contract** | Any app under `apps/` is self-contained (own manifest, config, README, tests, entry point); no cross-app imports — share only via `packages/`; the app-vs-package test decides `apps/` vs `packages/`. | `references/3-app/01-structure-and-stack/00_app-anatomy.md` |
| **Stack choice** | Which language / framework / runtime / engine an app uses, per kind, with criteria; firm defaults, deviate with a recorded reason. | `references/3-app/01-structure-and-stack/01_stack-decision.md` |
| **Backend skeleton** | Flat `app/` (run-service, no `src/`): `main.py` + `core/` + feature folders; `src/<pkg>/` only for distributables. Includes the `pyproject.toml` + `uv sync` flow. | `references/3-app/02-backend/00_app-skeleton.md` |
| **Backend domain layer** | Flat until tripwire T2 or the domain model settles → `app/<domain>/<feature>/` with aggregator routers. Domains named by ownership nouns, never activities or nav labels. | `references/3-app/02-backend/01_domain-grouping.md` |
| **Migration style + owner** | Plain Alembic (autogenerate + review) default; raw-SQL three-file pattern when non-Python consumers read the schema; two backends over one DB → neutral `apps/db`, `ctl migrate` only. | `references/3-app/04-database/01_migrations.md` |
| **App-level serving** | Per-language worker model + recycling + timeouts + health endpoints. Python is the outlier needing worker-process recycling; Rust/Go/Node scale via replicas. | `references/3-app/10-deployment/00_serving.md` |
| **ML Python flow** | `requirements.txt` + uvenv global env for ML projects (Layout 04) — deliberately different from the app flow. | `references/3-app/02-backend/03_ml-python-flow.md` |
| **Two-plane split** | Admin/user backends split only on security-posture grounds; then the DB moves to a neutral `apps/db`. | `references/3-app/02-backend/02_two-plane-split.md` |
| **Frontend skeleton** | The hard `src/` skeleton: `layout/ components/ features/ pages/ hooks/ api/ lib/ stores/ (styles/)`. Pages thin and URL-mirroring; all server communication through `api/`. | `references/3-app/03-web-app/00_app-skeleton.md` |
| **Workspace reconciliation** | In a workspace, `ui`/`styles`/`services` are packages — never duplicated as local folders. Both variants legitimate; never both at once. | `references/3-app/03-web-app/00_app-skeleton.md` § workspace reconciliation |
| **Shared-lib placement** | Lowest level containing all consumers: feature-internal → the feature; domain-shared → domain root; app-wide → `core/`/`lib/`; cross-app → a workspace package (scope per L2 topology). | `references/3-app/02-backend/01_domain-grouping.md`, `references/2-repo/01-layouts/00_grouping-topology.md` |
| **Type / DTO ownership** | `models.py` = the feature's API contract; frontend types inferred from zod in `api/`; cross-app entities in `packages/types`; no cross-domain DTO imports; no shared models package between backends. | `references/4-feature/types-and-contracts.md` |
| **DB engine + provisioning** | Pick the right floor (SQLite/Postgres, in-process/Redis) + `infra/` config vs `data/` state. Engine choice is a repo-wide decision, housed at L3. | `references/3-app/04-database/00_provisioning.md` |
| **Per-app DB usage** | The app's engine conventions — connection ownership, key naming, extension use — per engine. | `references/3-app/04-database/{04_sqlite,05_postgres,06_redis,07_other-engines}.md` |
| **Package internals** | Same two-level promise as an app; ONE export surface; services/types packages mirror the owning backend's domain names. | `references/3-app/05-package/00_shared-packages.md` |
| **Embeddable seams** | Embedding seams / IoC config API / per-instance mounts (repo shape + publishing stay at L2 Layout 06). | `references/3-app/05-package/02_embeddable-seams.md` |
| **Non-web surfaces** | Desktop (Tauri/Electron, reuses web `packages/`), native mobile (Kotlin/Swift under `apps/`), PWA (web frontend + manifest/SW, not a new app). | `references/3-app/06-desktop-app/00_desktop-app.md`, `references/3-app/07-mobile-app/00_mobile-app.md`, `references/3-app/03-web-app/02_pwa.md` |
| **AI integration** (if the product touches LLMs) | MCP server placement; LLM code as an adapter-per-provider boundary; keys backend-only via a proxy route. | `references/3-app/08-ai/00_mcp-servers.md`, `references/3-app/08-ai/01_agent-sdks.md`, `references/3-app/08-ai/02_ai-keys-and-safety.md` |
| **Security hardening** | Edge/captcha tier, app-owned rate limits (per-user/per-key), telemetry + audit as an adapter. | `references/3-app/09-security-hardening/00_edge-protection.md`, `references/3-app/09-security-hardening/01_rate-limiting.md`, `references/3-app/09-security-hardening/02_telemetry-and-audit.md` |
| **App packaging** | Dockerfile-per-app (multi-stage, non-root, pinned base), image naming/tags, healthcheck contract, `.dockerignore` (orchestration is L2). | `references/3-app/10-deployment/01_app-packaging.md` |

## Invariants (firm at this level)

- Every app/package owns its **manifest, `config.yaml` (backends), README, Dockerfile** — no sharing, no symlinks.
- **Skeleton names are firm** at the top level of `app/` and `src/`; contents below vary by project.
- **The api layer is the only server-communication surface** in a frontend.
- **Contracts have one owner each** — a schema, a DTO, an exported type each live in exactly one place.

## Per-app questions (the few not derivable from L2)

1. Stack — is the app's language/framework/runtime dictated by L2, or open? If open, pick per `references/3-app/01-structure-and-stack/01_stack-decision.md` and record it.
2. Migration style — autogenerate vs raw-SQL (driven by: non-Python schema consumers? hand-tuned DDL? review requirements?). See `references/3-app/04-database/01_migrations.md`.
3. Client-state library (zustand default) and data-fetching library (TanStack Query default) — names go into the structure block.
4. For a package: what is the export surface, and does it publish externally (then Layout 06 publishing rules apply)?
5. Does the product touch LLMs? Only then, the AI folder applies — MCP/agent placement + key safety (`references/3-app/08-ai/`).
6. Which security-hardening tier does this app need — none / captcha / full WAF, app-owned rate limits, telemetry+audit (`references/3-app/09-security-hardening/`)?

## Named variants (choices, not drift — record each in CLAUDE.md)

backend skeleton (flat `app/` / src-layout) · migration style (Alembic / raw-SQL / neutral `apps/db`) · workspace reconciliation (local folders / workspace packages) · client-state + data-fetching libraries · package export surface.

## Tripwires at this level

T2 (features → domains, `references/3-app/02-backend/01_domain-grouping.md`), T4 (ui package grouping, `references/3-app/05-package/00_shared-packages.md`). T3/T5/T6 live at L4 but are counted per-app during audits. Master table: `references/00_altitude-model.md`.

## Hands down to L4

Each feature folder receives its shape contract (`{router,service,repository,models}.py` / the feature's frontend subdivision axes), the type-placement rules, and the tripwire numbers — via the CLAUDE.md structure block, since L4 agents may never load this skill. See `references/4-feature/00_charter.md`.

## Audit at this level

- Count feature folders per app (T2) and files per feature (T3) → crossings without a recorded deferral = finding.
- Frontend skeleton: missing `pages/` or `api/` in a grown app; fetch outside `api/` (grep); local `ui`/`styles` duplicating workspace packages (red).
- Backend: cross-domain DTO imports; a shared models package between two backends (red); migrations on boot in a two-backend repo (red); activity-named domains; src-layout on a run-service backend.
- Packages: undocumented deep-import paths in consumers; missing export surface.
- The CLAUDE.md structure block exists and matches reality (missing = red).

## See also

- `references/00_altitude-model.md` — the 4+1 levels, master tripwire table, ownership table
- `references/2-repo/00_index.md` (step up) · `references/4-feature/00_charter.md` (step down)
