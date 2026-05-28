# Question flow

Run this in order before proposing any layout. **Skip what you already know**, but if any answer is ambiguous, stop and confirm. Ask in batches of 3–4 with reasonable defaults flagged — long flat question lists lose users.

## Batch 1 — repo cardinality + languages

1. **One repo, or multiple repos working together?**
   - One → single repo: Layout 01 (exactly one app) or Layout 02 (two or more apps) — continue Q2–Q4 to shape it
   - Multiple → Layout 03 (jump to Batch 5 — polyrepo specifics)
2. **How many backends?** (count distinct services with their own runtime, not modules within one service) — a *parameter of Layout 02*, not a separate layout
   - 0 (frontend-only, or pure tool)
   - 1
   - 2+ (ask which languages and what they coordinate via — Postgres / Redis Streams / HTTP; many small ones each with their own boundary = the mesh end of Layout 02)
3. **How many frontends?** (also a parameter of Layout 02)
   - 0
   - 1
   - 2+ (multi-frontend workspace; ask if they share UI/types/styles → `packages/`)
3a. **Deployed application, or distributed package?** (the often-unasked axis — ask it explicitly)
   - **Deployed** — the repo *runs* the product (you `docker compose up` / `ctl prod` it). Layouts 01–05.
   - **Distributed** — the deliverable is a **published package** that a *separate, external host* installs and runs. The repo's own web app (if any) is just a **reference host** for development, not the product. → Layout 06 (embeddable package + reference host).
   - Tell-tale: "another repo will consume this", "it gets embedded in someone else's app", "we publish it to npm/PyPI", "the frontend *is* the product, the local app just hosts it". If any of these, it's distributed even if it also happens to deploy a demo.
4. **What languages?**
   - Python, Rust, Go, TypeScript, Kotlin, Swift, mix
   - For Python: **app or ML?** (don't infer from extensions — ML uses uvenv + `requirements.txt`)
   - For Rust + Python combo: confirm coordination mechanism (Redis Streams? Direct DB? HTTP?)

## Batch 2 — frontend shape (skip if no frontend)

5. **Framework for each frontend?**
   - Vite + React (default)
   - Next.js (when SSR/SEO matters)
   - Astro (when content-heavy / mostly static)
6. **Package manager?**
   - Bun (default for Vite)
   - pnpm (default for multi-frontend; turborepo needs it)
   - npm / yarn (only if a framework requires)
7. **If multi-frontend: which shared packages?**
   - `packages/ui` (components)
   - `packages/styles` (tokens.css, light/dark)
   - `packages/tailwind-config`
   - `packages/typescript-config`
   - `packages/services` (API clients)
   - `packages/types`
   - Other
8. **Theming**: both light + dark, or light-only?
   - Default: both (`[data-theme="dark"]` on `:root`)
   - Light-only: only for marketing / home pages
9. **Frontend env exposure**: do you have any backend URLs the frontend needs?
   - List them — each will be a `VITE_*` / `NEXT_PUBLIC_*` baked at build time.
   - **Confirm** the user understands these end up in the bundle and visible to clients.

## Batch 3 — dev mode + scripts

10. **Dev mode**: containerise everything in dev, or apps on host + DBs in containers?
    - **Default: apps on host + DBs in containers** (faster iteration, hot reload, direct IDE debugger attach).
    - Containerise everything when the team needs total parity (rare).
11. **Hot reload needed?**
    - Confirm: bun dev / uvicorn --reload / cargo-watch — all run on host
12. **`ctl` subcommands**: which day-to-day flows need shortcuts?
    - Suggest defaults: `ctl dev` (host dev loop), `ctl prod` (full stack in docker), `ctl up`/`ctl down` (data containers), `ctl migrate {up|down|new}`, `ctl test`, `ctl clean`, `ctl help`.
    - Add language-specific: `ctl sqlx-prepare` (if Rust), `ctl train` (if ML).

## Batch 4 — deployment + secrets

13. **Deployment targets**: how many distinct deployment environments?
    - Single (e.g. one bare server)
    - Multiple (e.g. WSL dev / bare server / cloud — generates multiple `docker-compose-*.yml`)
14. **Reverse proxy**: external Traefik present? nginx-as-edge? raw ports?
    - Traefik present → include `docker/compose.traefik.yaml` overlay
    - nginx-as-edge → include `infra/nginx/nginx.conf` and route `/api/*`
    - Raw ports → `docker/compose.dev.yaml` only
14a. **Production serving**: how does the backend run in prod (vs the dev hot-reload process)?
    - Python → gunicorn + uvicorn workers; set worker count (≈ matches CPU limit), recycling (`--max-requests` + jitter), `--graceful-timeout`. See `references/architecture/production/app-server-and-workers.md`.
    - Rust / Go → one process, scale via replicas (no worker-process model). Node → replicas, not PM2-in-container.
    - Confirm: liveness `/health` + readiness `/ready` endpoints, graceful shutdown, resource limits, migrations as a pre-traffic step. Walk `references/architecture/production/production-readiness.md`.
15. **Secrets**:
    - Local: confirm `.env` + `.env.local` + `config.local.yaml` gitignored, generated via `openssl rand -hex 32` (instructions at top of `.env.example`)
    - CI: GitHub Actions secrets, self-hosted runner env, or none?
    - Prod: `.env.production` (compose `env_file`), or Vault / 1Password later?
16. **Open source vs private**: affects CI defaults + license file.

## Batch 5 — polyrepo specifics (only if Q1 = multiple)

17. **How many repos?** List them.
18. **Is there an aggregator repo?** (recommended) — owns the canonical merged `.env.example` and prod `docker-compose.yaml` referencing built images.
    - If no, propose adding one (`<product>-deploy`).
19. **How do child `.env.example` keys stay in sync with the aggregator?**
    - Default: a `sync-env-templates.sh` script in the aggregator that fetches each child's `.env.example` and asserts the union.

## Batch 6 — supporting infra

20. **Databases needed? — pick the right floor, don't over-provision** (see `references/architecture/database/choosing-a-database.md`)
    - **Relational**: SQLite (single service, modest data, low write concurrency — e.g. auth/config/metadata) vs Postgres (concurrent writers, cross-service sharing, large data, extensions). Start SQLite; move to Postgres when you need concurrent writers or sharing.
    - **Cache / shared state**: in-process memory (single worker, ephemeral, small — a dict rebuilt on boot) vs Redis (shared across workers/services, TTL, persistence, pub/sub). This is coupled to worker count (Q14a) — N workers with coherence needs → Redis.
    - MongoDB / Neo4j / Kuzu / SeaweedFS — per requirement
    - Migrations: Alembic by default (Python); SQLite needs `render_as_batch=True`; when not Alembic, see `references/architecture/backend/when-not-alembic.md`
21. **Image versions**: **never inherit defaults silently.** For each database / runtime selected, **check the current latest stable** and ask the user which to pin to. The versions in this skill's references are illustrative only.
22. **Docs**: in-repo `docs/` (recommended for monorepo) or separate docs repo?
    - In-repo → hand off to `/docs-init` (documentation-guide plugin)
    - Separate → confirm repo name and add to `examples-index.md`
23. **`.claude/`**: confirm it stays empty initially. The bootstrapper creates the folder and a `CLAUDE.md` next to it; we build up agents/commands/settings as patterns emerge.
24. **`.mise.toml`**: which runtime versions to pin? **Check `mise ls-remote python | tail`, `mise ls-remote node | tail`, etc. for current options.** Ask the user which to pin — defaults are illustrative.
25. **Pre-commit hooks (lefthook)?** Recommended for any project with a team. Default yes for Layout 02; ask for Layout 01 / 04.
26. **`.vscode/` configs?** Optional. If yes, drop `launch.json` / `settings.json` / `extensions.json` per `references/repo-setup/tooling/vscode-debugger.md`.

## Batch 7 — ML orchestration (only for Layout 04 ML projects)

27. **Cloud orchestration**: dstack / SkyPilot / both / neither / custom?
    - Default **dstack** — already a sibling plugin; defer to its skill for CLI mechanics.
    - SkyPilot if the team's already there or needs heavier k8s integration.
    - Custom only with strong justification (`references/architecture/ml-orchestration/custom-orchestrator.md`).
28. **Spot or on-demand**? Both is fine — spot for training/sweeps, on-demand for inference SLAs / final paper-result training.
29. **Training cadence**: one-shot / sweep / continuous / batch?
    - One-shot + sweep → spot + checkpoints + retry (`spot-instances-and-checkpoints.md`)
    - Continuous → managed service mode (`inference-autoscaling.md`)
30. **Inference**: none / batch (queue+workers) / online (web endpoint + autoscale)?
31. **Remote dev**: does the user want a one-command "spin up GPU box + SSH + VS Code Remote" flow?
    - If yes → `references/architecture/ml-orchestration/remote-dev-ssh-vscode.md`
32. **Agent access to remote**: does an agent (Claude) need to operate the remote box on the user's behalf?
    - If yes → `references/architecture/ml-orchestration/agent-ssh-access.md`; configure `.claude/settings.local.json` permissions explicitly
33. **CI/CD for ML**: which tiers — cheap (every PR) / medium (nightly) / expensive (on tag)?
    - `references/architecture/ml-orchestration/cicd-for-ml.md` has templates per tier

## Special — never assume, always ask

| Topic | Why ask |
|---|---|
| **Deployed vs distributed** | The repo might *run* the product, or *publish a package* an external host runs. Unasked, the skill defaults to "deployed" and mis-frames `apps/` vs `packages/`, missing peerDeps / exports / publishing entirely. → Layout 06. |
| Sibling-repo dependencies | Cannot infer from inside one repo. |
| ML vs app | `.py` files exist in both. Affects every Python decision. |
| Frontend exposure | A leaked DATABASE_URL via `VITE_*` is catastrophic. |
| Deployment targets | Generating Traefik config for a project with no Traefik is waste. |
| Theming requirements | Both modes is default; marketing pages opt out. |
| Build-time vs runtime per env var | Each must be classified explicitly. |

## Confirmation step

Before proposing any layout, **summarise what you heard** in 5–10 bullets and ask the user to confirm. Examples:

> Based on what you've told me:
> - Monorepo, single backend (Python/FastAPI), single frontend (Vite + React + TS), no ML
> - Apps on host in dev, postgres+redis in containers
> - External Traefik in prod, nginx-as-edge inside the compose
> - Both light + dark mode
> - In-repo `docs/`, .claude/ empty
> - Open source, GitHub Actions CI
>
> Proceed with Layout 02? (yes / change X)

Only then move to the proposal.
