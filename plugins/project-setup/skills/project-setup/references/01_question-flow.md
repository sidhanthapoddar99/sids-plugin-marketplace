# Question flow

Run this in order before proposing any layout. **Skip what you already know**, but if any answer is ambiguous, stop and confirm. Ask in batches of 3–4 with reasonable defaults flagged — long flat question lists lose users.

## Batch 1 — repo cardinality + languages

1. **One repo, or multiple repos working together?**
   - One → monorepo or single-app (continue with Q2–Q4 to pick the topology)
   - Multiple → Topology 06 (jump to Batch 5 — polyrepo specifics)
2. **How many backends?** (count distinct services with their own runtime, not modules within one service)
   - 0 (frontend-only, or pure tool)
   - 1
   - 2 (microservices coordinating; ask which languages and what they coordinate via)
   - 3+ (microservices mesh)
3. **How many frontends?**
   - 0
   - 1
   - 2+ (multi-frontend workspace; ask if they share UI/types/styles)
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
12. **`./dev` subcommands**: which day-to-day flows need shortcuts?
    - Suggest defaults: `./dev` (bare = first-run flow), `./dev migrate {up|down|new}`, `./dev test`, `./dev clean`, `./dev help`.
    - Add language-specific: `./dev sqlx-prepare` (if Rust), `./dev ml-train` (if ML).

## Batch 4 — deployment + secrets

13. **Deployment targets**: how many distinct deployment environments?
    - Single (e.g. one bare server)
    - Multiple (e.g. WSL dev / bare server / cloud — generates multiple `docker-compose-*.yml`)
14. **Reverse proxy**: external Traefik present? nginx-as-edge? raw ports?
    - Traefik present → include `docker/compose.traefik.yaml` overlay
    - nginx-as-edge → include `infra/nginx/nginx.conf` and route `/api/*`
    - Raw ports → `docker/compose.dev.yaml` only
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

20. **Databases needed?**
    - Postgres (default for relational)
    - Redis (default for cache, sessions, streams)
    - MongoDB / Neo4j / Kuzu / SeaweedFS — per requirement
    - Migrations: Alembic by default (Python); when not Alembic, see `references/python/when-not-alembic.md`
21. **Docs**: in-repo `docs/` (recommended for monorepo) or separate docs repo?
    - In-repo → hand off to `/docs-init` (documentation-guide plugin)
    - Separate → confirm repo name and add to `examples-index.md`
22. **`.claude/`**: confirm it stays empty initially. The bootstrapper creates the folder and a `CLAUDE.md` next to it; we build up agents/commands/settings as patterns emerge.
23. **`.mise.toml`**: which runtime versions to pin?
    - Default Python 3.14, Bun (latest stable), Rust (`rust-toolchain.toml`), Go 1.23+

## Special — never assume, always ask

| Topic | Why ask |
|---|---|
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
> Proceed with Topology 02? (yes / change X)

Only then move to the proposal.
