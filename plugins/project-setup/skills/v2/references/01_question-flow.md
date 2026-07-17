# Question flow

Run this in order before proposing any layout. The order is **level-ordered** (see `references/00_altitude-model.md`): L1 ecosystem → L2 repo → L3 per-app, with two conditional L2 batches (6: polyrepo aggregator, 9: ML orchestration) deferred to the end because most projects skip them. **L4 is never asked** — feature-level conventions are installed via the CLAUDE.md blocks, not decided in an interview.

**Skip what you already know**, but if any answer is ambiguous, stop and confirm. Ask in small batches with reasonable defaults flagged — long flat question lists lose users. Every named variant the user picks (topology, rooting, BFF/core, migration owner, exceptions) gets **recorded in the project CLAUDE.md** at the end.

## L1 — Batch 1: ecosystem

1. **One repo, or multiple repos working together?**
   - One → single repo: Layout 01 (exactly one app) or Layout 02 (two or more apps) — continue to shape it
   - Multiple → Layout 03 (also run Batch 6 — polyrepo specifics). Mono-vs-poly criteria: `references/1-ecosystem/repo-boundaries.md`.
2. **Sibling repos / dependencies?** Does this repo expect another repo to exist (deploy aggregator, published SDK it consumes, docs repo)? Cannot be inferred from inside one repo — always ask.
3. **Deployed application, or distributed package?**
   - **Deployed** — the repo *runs* the product (you `ctl up` it; production is `ctl up prod`). Layouts 01–05.
   - **Distributed** — the deliverable is a **published package** an external host installs and runs; the repo's own app is a **reference host**, not the product. → Layout 06.
   - Criteria + tell-tales owned by `references/1-ecosystem/repo-boundaries.md`.
4. **Docs: in-repo `docs/` or a separate docs repo?**
   - Default **in-repo** for a single-repo product; **separate `<product>-docs`** when the product spans multiple repos or docs release independently (`references/1-ecosystem/docs-placement.md`). Never both.

## L2 — Batch 2: apps, planes, topology

5. **How many backends?** (count distinct services with their own runtime, not modules) — a *parameter of Layout 02*. For 2+: which languages, and what they coordinate via (Postgres / Redis streams / HTTP).
6. **Does any surface need a separate identity/security plane** — operator/admin vs end-user (own credentials table, internal-only exposure, independent deploy cadence)?
   - Yes → the two-plane split: separate backends + the neutral `apps/db` migrations owner (`references/3-app/02-backend/02_two-plane-split.md`). The backend count falls out of this answer — don't guess it from Q5 alone.
   - A different look/nav for admins is **not** a yes — that's role-gated routes.
7. **How many frontends?** For 2+: do they share UI/types/styles → workspace + `packages/`.
8. **Frontend↔backend relationship** — where does the contract gravity sit?
   - **Core backend** (default): backend is the engine; frontend is one consumer.
   - **BFF**: the backend exists to serve this frontend (aggregation/session/proxy).
   - **No backend here**: frontend against an external API (may actually be Layout 01).
9. **Grouping topology** (when 2+ apps): flat `apps/` (default), plane-grouped (`apps/server/` + `apps/client/`), or hybrid?
   - Apply the tripwire T1 default, but **ask when both fit**; record the pick. Threshold + variants: `references/2-repo/01-layouts/00_grouping-topology.md`.
10. **What languages?**
    - For Python: **app or ML?** (never inferred from extensions — ML → Layout 04, uvenv + `requirements.txt`)
    - For Rust + Python: confirm the coordination mechanism.

## L2 — Batch 3: frontend shape (skip if no frontend — **except Q16, always ask**)

11. **Framework per frontend?** Vite + React (default) / Next.js (SSR/SEO) / Astro (content-heavy static) — criteria: `references/3-app/01-structure-and-stack/01_stack-decision.md`.
12. **Package manager?** Bun (default single frontend) / pnpm (default for workspaces; turborepo needs it) / npm-yarn (only if a framework requires) — same owner as Q11.
13. **If workspace: which shared packages, at which scope, rooted where?**
    - Packages: `ui`, `styles`, `tailwind-config`, `typescript-config`, `services`, `types`, …
    - **Scope**: frontend-only packages live inside the client group; cross-plane packages force root `packages/` (consumer rule — `references/2-repo/01-layouts/00_grouping-topology.md`).
    - **Rooting**: JS-only repo → workspace at repo root (orchestration-only manifest); polyglot → workspace at the frontend group folder (`references/2-repo/01-layouts/00_grouping-topology.md`).
14. **Theming**: both light + dark (default, `[data-theme]`), or light-only (marketing pages)?
15. **Frontend env exposure**: which backend URLs does the frontend need? Each becomes a `VITE_*`/`NEXT_PUBLIC_*` baked into the **client-visible bundle** — confirm the user understands, and that no secret is among them.
16. **Non-web surfaces?** Web is the default. Ask whether the product also needs: a **mobile** app (native iOS/Android, own codebase under `apps/` → `references/3-app/07-mobile-app/00_mobile-app.md`); a **desktop** app (Tauri default / Electron → `references/3-app/06-desktop-app/00_desktop-app.md`); or a **PWA** — the *existing* web frontend made installable + offline via a manifest + service worker, **not** a separate app (`references/3-app/03-web-app/02_pwa.md`). PWA and native are not exclusive — a product can ship both over the same backend contract.

## L2 — Batch 4: dev mode + runtime

17. **Dev mode**: apps on host + DBs in containers (default — hot reload, debugger attach), or fully containerised (rare, total-parity teams)?
18. **Hot reload**: confirm the host-side runners (bun dev / uvicorn --reload / cargo-watch).
19. **`ctl` subcommands**: which day-to-day flows need shortcuts?
    - Defaults: `dev`, `up [config] [--modifier "a,b"]` (interactive bare; prod = `ctl up prod`), `down`, `migrate`, `test`, `clean`, `help`; add language-specific (`sqlx-prepare`, `train`).
    - Install is **copy-verbatim from `assets/snippets/scripts/`**, then adapt by deletion — the conformance floor in `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`.

## L2 — Batch 5: deployment + secrets

20. **Deployment targets**: single environment or multiple (dev WSL / bare server / cloud)?
21. **Reverse proxy**: external Traefik (→ `traefik` modifier) / nginx-as-edge (→ `infra/nginx/`) / raw ports (→ `expose` modifier)?
22. **Production serving**: per language — Python: gunicorn + uvicorn workers (count, recycling, graceful timeout — `references/3-app/10-deployment/00_serving.md`); Rust/Go/Node: replicas. Confirm health endpoints, graceful shutdown, limits, migrations-as-pre-traffic-step (`references/2-repo/04-docker/05_production-readiness.md`).
23. **Secrets**: local (`.env` + `config.local.yaml`, `openssl rand -hex 32` instructions in `.env.example`) / CI (which store) / prod (`.env.production` via compose `env_file`, or Vault later)?
24. **Open source vs private**: license, CI defaults. For a pure OSS **package** repo, this is also where the root-manifest exception may apply — record it if taken (`references/2-repo/02-root-hygiene/00_root-and-hygiene.md`).

## L1 — Batch 6: polyrepo specifics (only if Q1 = multiple)

25. **How many repos?** List them and their roles (one sentence each).
26. **Is there an aggregator repo?** (recommended) — owns the canonical merged `.env.example` + prod compose over built images. If none, propose `<product>-deploy`.
27. **How do child `.env.example` keys stay in sync?** Default: a sync script in the aggregator that fetches each child's `.env.example` and asserts the union.

## L2 — Batch 7: supporting infra + hygiene

28. **Databases — pick the right floor** (`references/3-app/04-database/00_provisioning.md`): SQLite vs Postgres (concurrent writers, sharing, extensions); in-process memory vs Redis (coupled to worker count, Q22); Mongo/Neo4j/Kuzu/Seaweed per requirement.
29. **Image + runtime versions**: **never inherit defaults silently** — check current latest stable (`mise ls-remote …`, registry tags) and let the user pick. Versions in this skill's references are illustrative.
30. **Hygiene** (not a question — state it): `.gitignore` generated from `assets/snippets/env/gitignore.template`, keeping only the sections for ecosystems present; `data/**` + `.gitkeep` negation; `.vscode/`/`.claude/` selectively committed.
31. **Docs handoff**: for in-repo docs, create the `docs/` slot and point at the docs plugin's init command (`references/1-ecosystem/docs-placement.md`).
32. **`.claude/` + CLAUDE.md**: `.claude/` stays empty initially; CLAUDE.md is generated from the template **with the repo + structure + styling blocks resolved** — this is where every variant chosen above gets recorded.
33. **Pre-commit hooks (lefthook)?** Default yes for Layout 02; ask for 01/04.
34. **`.vscode/` debug configs?** Optional — `references/2-repo/05-ctl-scripts-tooling/05_vscode-debugger.md`.

## L3 — Batch 8: per-app (run once per app; mostly confirm defaults)

The skeletons themselves are **defaults, not questions** (backend `app/` + feature folders per `references/3-app/02-backend/00_app-skeleton.md`; frontend `src/` skeleton per `references/3-app/03-web-app/00_app-skeleton.md`). Ask only:

35. **Stack, per app** (only if L2 didn't dictate it): language/framework/runtime for this app — confirm the default for its kind or pick per `references/3-app/01-structure-and-stack/01_stack-decision.md`; record the pick + reason.
36. **Migration style, per backend**: Alembic autogenerate (default, Python-only) vs raw-SQL three-file pattern (non-Python schema consumers / hand-tuned DDL / SQL review culture)? **If two backends share one DB, the owner is the standalone `apps/db` — state it, don't ask it** (`references/3-app/02-backend/02_two-plane-split.md`). Migration-tool decision: `references/3-app/04-database/01_migrations.md`.
37. **Frontend state + data libraries**: zustand (client state) + TanStack Query (server state) defaults — confirm; the names go into the structure block.
38. **For each workspace package**: its export surface (barrel + documented sub-paths) and whether it publishes externally (→ Layout 06 publishing rules apply to it).
39. **Does the product touch LLMs?** Only then does the AI surface apply: MCP server placement (`references/3-app/08-ai/00_mcp-servers.md`), agent/LLM code as an adapter-per-provider boundary (`references/3-app/08-ai/01_agent-sdks.md`), and keys backend-only via a proxy route (`references/3-app/08-ai/02_ai-keys-and-safety.md`). If no LLM, skip `08-ai/` entirely.
40. **Security-hardening tier, per public app**: none / captcha (Turnstile) / full WAF for the edge (`references/3-app/09-security-hardening/00_edge-protection.md`); app-owned per-user/per-key rate limits (`references/3-app/09-security-hardening/01_rate-limiting.md`); telemetry + audit (`references/3-app/09-security-hardening/02_telemetry-and-audit.md`). Tier is exposure-driven, not a default.

## L2 — Batch 9: ML orchestration (only for Layout 04 ML projects)

41. **Cloud GPUs**: none (local / bare-metal only) / cloud — via `scripts/cloud/` wrappers over the provider CLI, escalating to a thin custom CLI only past the script ceiling (`references/2-repo/07-ml-orchestration/00_custom-orchestrator.md`).
42. **Spot or on-demand?** Spot for training/sweeps; on-demand for inference SLAs / final runs.
43. **Training cadence**: one-shot / sweep / continuous / batch → checkpoints + retry vs managed service (`references/2-repo/07-ml-orchestration/`).
44. **Inference**: none / batch (queue + workers) / online (endpoint + autoscale)?
45. **Remote dev**: one-command GPU box + SSH + VS Code Remote flow wanted?
46. **Agent access to the remote box?** → `references/2-repo/07-ml-orchestration/04_agent-ssh-access.md`; permissions configured explicitly.
47. **CI/CD for ML**: cheap (every PR) / medium (nightly) / expensive (on tag) tiers.

## Special — never assume, always ask

| Topic | Why ask |
|---|---|
| **Deployed vs distributed** | Unasked, "deployed" gets assumed and `apps/` vs `packages/` gets mis-framed, missing peerDeps / exports / publishing. → Layout 06. |
| **Sibling-repo dependencies** | Cannot infer from inside one repo. |
| **Identity planes (admin vs user)** | Drives backend count, migrations owner, exposure — a count question can't surface it. |
| **ML vs app** | `.py` files exist in both; affects every Python decision. |
| **Grouping topology** (when 2+ apps and both shapes fit) | Both are legitimate; the pick must be recorded, not implied. |
| **External services present** (Traefik / self-hosted Postgres / cloud DB) | Changes the proxy posture and provisioning defaults; cannot be inferred from the repo. |
| **Open source vs private** | Sets CI/secrets defaults (`references/2-repo/03-env-config/03_secrets-matrix.md`). |
| **Frontend exposure** | A leaked secret via `VITE_*` is catastrophic. |
| **Deployment targets** | Generating Traefik config for a repo with no Traefik is waste. |
| **Theming** | Both modes default; marketing pages opt out. |
| **Build-time vs runtime per env var** | Each must be classified explicitly. |
| **Image/runtime versions** | Never pin from training data — check latest stable and ask. |

## Confirmation step

Before proposing any layout, **summarise what you heard** in 5–10 bullets — including every recorded variant — and ask the user to confirm:

> Based on what you've told me:
> - Monorepo, Layout 02 — 2 backends (platform + admin: separate identity planes → `apps/db` owns migrations), 2 frontends
> - Topology: plane-grouped (`apps/server/`, `apps/client/`); workspace rooted at `apps/client/` (polyglot repo); `ui`/`styles`/`types` scoped inside the client group
> - Backend role: core (frontends are consumers); everything under `/api/*`
> - Apps on host in dev; postgres + redis in containers; external Traefik in prod
> - Both light + dark; in-repo `docs/`; open source
>
> Proceed? (yes / change X)

Only then move to the proposal — and carry every confirmed variant into the CLAUDE.md blocks.
