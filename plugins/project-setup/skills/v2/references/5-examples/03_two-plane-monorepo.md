# Example 03 — two-plane monorepo (plane-grouped)

A worked, anonymized tree for **Layout 02 in its plane-grouped variant**: a product with two identity planes — an end-user **platform** and an operator **admin** — over one database. Two backends (`apps/server/{api-platform,api-admin}`), a neutral migrations owner (`apps/db`), and two frontends sharing a workspace rooted at `apps/client/`. Generic domain: an online marketplace (buyers/sellers on the platform; operators moderating listings and resolving disputes on the admin plane).

This is an example, not an owner. Every rule shown here is *governed* by the reference linked in the annotation or the closing map — this file restates nothing normative. Read it top-down: recorded choices → whole tree → zoom-ins → which reference governs each part.

## What this example demonstrates

| Aspect | Choice shown | Owner |
|---|---|---|
| Repo layout | Layout 02, **plane-grouped** topology (T1 tripped) | `references/2-repo/grouping-topology.md` |
| Backend count | two — separate security postures (admin vs user) | `references/3-app/backend/two-plane-split.md` |
| DDL owner | neutral `apps/db`, run only via `ctl migrate` | `references/3-app/backend/two-plane-split.md`, `references/3-app/backend/migrations.md` |
| Workspace rooting | polyglot repo → JS workspace roots at `apps/client/`; repo root manifest-free | `references/2-repo/grouping-topology.md`, `references/2-repo/root-and-hygiene.md` |
| Package placement | frontend-only packages inside the client group | `references/2-repo/grouping-topology.md` |
| Backend internals | domain layer inside each backend (T2) | `references/3-app/backend/domain-grouping.md` |
| Frontend internals | the hard `src/` skeleton inside each frontend | `references/3-app/frontend/app-skeleton.md` |
| Migration mechanics | raw-SQL three-file pattern (language-neutral) | `references/3-app/backend/raw-sql-recipe.md` |

## Recorded-variant table — as this repo's CLAUDE.md carries it

The repo shape is unusual (grouped planes, non-root workspace, two backends), so the CLAUDE.md records every chosen variant. Audits compare the repo against these records — a shape with a recorded choice is a variant, a missing record is the finding (`references/00_altitude-model.md` § audits-against-recorded-choices). This block is the always-loaded summary; it defers to the skill for the full rules.

```markdown
## Structure — recorded variants (project-setup skill is the authority)

| Decision | Choice | Tripwire | Owner reference |
|---|---|---|---|
| Repo layout | Layout 02, plane-grouped | T1 (tripped: 2 frontends + 2 backends) | references/2-repo/grouping-topology.md |
| Identity planes | split: api-platform (users) + api-admin (operators) | — | references/3-app/backend/two-plane-split.md |
| Database | one Postgres; per-table single writer; no shared models pkg | — | references/3-app/backend/two-plane-split.md |
| DDL owner | apps/db (neutral); migrate only via `ctl migrate` | — | references/3-app/backend/migrations.md |
| Migration style | raw-SQL three-file (language-neutral consumers) | — | references/3-app/backend/raw-sql-recipe.md |
| Workspace root | apps/client/ (polyglot repo; repo root manifest-free) | T10 (watched) | references/2-repo/grouping-topology.md |
| Frontend packages | ui/styles/types/services inside apps/client/packages/ | — | references/2-repo/grouping-topology.md |
| Backend↔frontend | core backend (domain-first APIs) | — | references/2-repo/layouts/02_multi-app-monorepo.md |
| Domain layers | api-platform: catalog/orders/access; api-admin: moderation/operators | T2 (tripped in api-platform) | references/3-app/backend/domain-grouping.md |

Deferred: api-admin stays flat (5 features) until it crosses ~8 — T2 deferral, revisit at v2.

If a decision falls outside this table, load the project-setup skill and resolve it at
the right level — never improvise a pattern inline.
```

## The whole tree

```
marketplace/
├── .env                              # shared backend/infra vars only, gitignored — env-precedence.md
├── .env.example                      # the committed contract
├── .env.production                   # optional, compose env_file for prod
├── .mise.toml                        # runtime contract: python + node + uv toolchains — runtime/mise.md
├── ctl                               # single dispatcher; delegates JS cmds into apps/client/ — runtime/script-overview.md
├── lefthook.yml                      # git hooks at the repo root (not husky — workspace isn't here) — tooling/lefthook.md
├── docker/                           # compose mechanics — runtime/docker-overview.md
│   ├── compose.yaml                  # base: whole stack, NO profiles, no host ports
│   ├── compose.data.yaml             # standalone (ctl up data): postgres + redis only
│   ├── compose.prod.yaml             # standalone (ctl up prod): image tags, limits, .env.production
│   ├── compose.m.expose.yaml         # .m. modifier: publish the public nginx edge
│   └── compose.m.expose_admin.yaml   # .m. modifier: bind admin edge to an internal tier only
├── scripts/                          # subscripts ctl calls
│   ├── db-init.sh                    # bootstrap operator break-glass account (admin plane)
│   └── check-env.sh
├── apps/
│   ├── server/                       # BACKEND plane group — Python services
│   │   ├── api-platform/             # end-user backend (buyers/sellers) — PUBLIC edge
│   │   │   ├── pyproject.toml + uv.lock
│   │   │   ├── config.yaml           # reads root .env via ${VAR} — env-and-config/per-service-config.md
│   │   │   ├── config.local.yaml     # gitignored override
│   │   │   ├── app/                  # FLAT app/ (run-service, no src/) — backend/app-skeleton.md
│   │   │   │   ├── main.py           # mounts one router per domain
│   │   │   │   ├── core/             # cross-cutting: db, settings, security, health
│   │   │   │   ├── catalog/          # DOMAIN (T2 tripped) — domain-grouping.md
│   │   │   │   │   ├── router.py     # aggregator router for the domain
│   │   │   │   │   ├── listings/     # feature: {router,service,repository,models}.py
│   │   │   │   │   └── search/       # feature
│   │   │   │   ├── orders/           # DOMAIN
│   │   │   │   │   ├── router.py
│   │   │   │   │   ├── checkout/  payments/  fulfilment/
│   │   │   │   └── access/           # DOMAIN — end-user identity (OAuth + signup)
│   │   │   │       ├── router.py
│   │   │   │       └── users/  sessions/
│   │   │   ├── tests/
│   │   │   ├── Dockerfile
│   │   │   └── README.md             # this backend's host dev loop — readme-three-paths.md
│   │   └── api-admin/                # operator backend — INTERNAL edge, separate identity plane
│   │       ├── pyproject.toml + uv.lock
│   │       ├── config.yaml
│   │       ├── app/                  # FLAT + still flat (5 features, T2 deferred)
│   │       │   ├── main.py
│   │       │   ├── core/
│   │       │   ├── moderation.py     # feature — reads catalog tables, writes moderation tables
│   │       │   ├── disputes.py       # feature
│   │       │   ├── operators.py      # feature — operator identity (break-glass CLI, no signup)
│   │       │   ├── reports.py        # feature — read-only aggregates over the schema
│   │       │   └── audit.py          # feature
│   │       ├── tests/
│   │       ├── Dockerfile
│   │       └── README.md
│   ├── db/                           # NEUTRAL migrations owner — imports NO backend code
│   │   ├── pyproject.toml            # alembic + psycopg only — two-plane-split.md
│   │   ├── alembic.ini
│   │   ├── alembic/
│   │   │   ├── env.py                # raw-SQL shim: runs the .sql files — raw-sql-recipe.md
│   │   │   └── versions/
│   │   │       └── 0001_initial/     # three-file pattern: up.sql / down.sql + revision.py
│   │   └── README.md                 # "run only via `ctl migrate` — never on a backend's boot"
│   └── client/                       # FRONTEND plane group — JS WORKSPACE ROOTS HERE
│       ├── package.json              # workspace root manifest (orchestration-only)
│       ├── pnpm-workspace.yaml       # globs relative to this folder: platform, admin, packages/*
│       ├── pnpm-lock.yaml            # lockfile + node_modules/ live here, NOT at repo root
│       ├── turbo.json                # globalEnv lists every VITE_* cache-buster — workspaces-mechanics.md
│       ├── tsconfig.json             # base TS config extended by each app
│       ├── platform/                 # PUBLIC frontend (buyers/sellers)
│       │   ├── package.json + .env   # VITE_* only — env-and-config/frontend-env-isolation.md
│       │   ├── vite.config.ts        # proxies /api/* to api-platform in dev — deployment/proxy-and-exposure.md
│       │   ├── tailwind.config.ts    # extends packages/tailwind-config
│       │   ├── index.html            # data-theme="light" — tokens-setup.md
│       │   └── src/                  # the hard skeleton — frontend/app-skeleton.md
│       │       ├── main.tsx  App.tsx
│       │       ├── layout/  components/  features/  pages/
│       │       ├── hooks/  api/  lib/  stores/
│       │       └── (no styles/ or components/ui/ — those are workspace packages)
│       ├── admin/                    # OPERATOR frontend — same src/ skeleton
│       │   ├── package.json + .env   # VITE_* only; admin URLs never leak to platform bundle
│       │   ├── vite.config.ts        # proxies /api/* to api-admin
│       │   └── src/ …                # same skeleton
│       └── packages/                 # FRONTEND-ONLY packages — inside the client group (lowest common consumer)
│           ├── ui/                   # shadcn primitives + wrappers (T4) — frontend/shared-packages.md
│           ├── styles/               # the single tokens.css, globals, light/dark — tokens-setup.md
│           ├── types/                # shared TS types (zod-inferred) — 4-feature/types-and-contracts.md
│           ├── services/             # shared auth/session + API clients (shapes, not sessions)
│           ├── tailwind-config/      # shared Tailwind preset
│           └── typescript-config/
├── infra/                            # CONFIG only, not data — databases-provisioning.md
│   ├── nginx/
│   │   ├── platform.conf             # routes public /api/* → api-platform
│   │   └── admin.conf                # routes internal /api/* → api-admin
│   └── postgres/init/01_extensions.sql
├── data/                             # bind-mount targets, gitignored except .gitkeep
│   └── postgres/pgdata/.gitkeep
├── docs/                             # documentation plugin via /docs-init — 1-ecosystem/docs-placement.md
├── .claude/                          # empty initially — handoffs/claude-folder.md
├── CLAUDE.md                         # carries the recorded-variant table above
├── README.md                        # root README: three paths — readme-three-paths.md
└── LICENSE
```

## Zoom-in — inside a backend (the domain layer)

`api-platform` crossed the T2 tripwire (~8–10 features), so its features group into **domains** (`catalog`, `orders`, `access`); each domain has an aggregator `router.py` and the app entrypoint mounts one router per domain. `api-admin` has 5 features and **stays flat** with a recorded deferral — a domain layer over 5 features is ceremony. Domain names are ownership nouns (`catalog`, not `listing-management`). Both backends keep the flat `app/` (run-service, no `src/`). Governed by `references/3-app/backend/domain-grouping.md` (grouping) and `references/3-app/backend/app-skeleton.md` (the `app/` shape); feature-folder internals by `references/4-feature/feature-folders.md`.

## Zoom-in — the database contract (why `apps/db` is neutral)

One Postgres, strict single-writer ownership: `api-platform` writes `listings`/`orders`/`users`; `api-admin` writes `moderation`/`disputes`/`operators` and *reads* the catalog/order tables it moderates. No shared ORM/models package — each backend declares its own DTOs against the schema (`references/4-feature/types-and-contracts.md`). DDL belongs to **neither** backend: `apps/db` is the sole owner, imports no backend code, and runs only via `ctl migrate {up|down|new|status}` — never on a backend's boot (two backends racing entrypoint migrations is exactly the failure this prevents). The raw-SQL three-file pattern fits because the `.sql` is readable by every consumer regardless of language. Governed by `references/3-app/backend/two-plane-split.md`, `references/3-app/backend/migrations.md`, `references/3-app/backend/raw-sql-recipe.md`.

## Zoom-in — inside a frontend (the `src/` skeleton) + workspace reconciliation

Each frontend under `apps/client/` keeps the identical hard `src/` skeleton (`main.tsx`, `App.tsx`, `layout/`, `components/`, `features/`, `pages/`, `hooks/`, `api/`, `lib/`, `stores/`). Three layers are **absent locally** because they graduated to shared packages — `components/ui/` → `packages/ui`, `styles/` → `packages/styles`, shared clients → `packages/services`. Never both: a local `styles/` beside `packages/styles` is a red finding. The two planes share the visual language (one `tokens.css`, one `ui`) even though sessions never cross. Governed by `references/3-app/frontend/app-skeleton.md` (skeleton + reconciliation), `references/3-app/frontend/shared-packages.md` (package internals, T4), `references/4-feature/styling-discipline.md` (usage rules).

## Zoom-in — workspace rooting (polyglot repo)

This is a polyglot repo (Python backends + TS frontends), so the JS workspace roots at the **frontend group folder** `apps/client/`, not the repo root: `package.json`, `pnpm-workspace.yaml`, lockfile, and `node_modules/` all live there and the repo root stays manifest-free. `ctl` bridges back — `ctl dev` / `ctl build` `cd` into `apps/client/` and delegate to turbo. Git hooks use **lefthook at the repo root** (husky expects the git root; this repo's workspace isn't there). Governed by `references/2-repo/grouping-topology.md` (rooting + frictions), `references/2-repo/root-and-hygiene.md` (manifest-free root, T10).

## Which references govern each part

| Part of the tree | Governing reference |
|---|---|
| Whole layout + when plane-grouping is right (T1) | `references/2-repo/grouping-topology.md` |
| `apps/server/{api-platform,api-admin}` split + `apps/db` | `references/3-app/backend/two-plane-split.md` |
| Migration style + DDL owner decision | `references/3-app/backend/migrations.md` |
| `apps/db/alembic/` raw-SQL three-file mechanics | `references/3-app/backend/raw-sql-recipe.md` |
| Flat `app/` shape, `core/`, `main.py` | `references/3-app/backend/app-skeleton.md` |
| Domains inside a backend (T2), aggregator routers | `references/3-app/backend/domain-grouping.md` |
| Feature-folder internals, T3 subdivision | `references/4-feature/feature-folders.md` |
| DTO placement, no shared models package | `references/4-feature/types-and-contracts.md` |
| `apps/client/` workspace rooting, packages placement | `references/2-repo/grouping-topology.md`, `references/2-repo/root-and-hygiene.md` |
| `apps/client/packages/{ui,styles,types,services}` internals | `references/3-app/frontend/shared-packages.md` |
| pnpm/turbo config bodies, `ctl` delegation | `references/3-app/frontend/workspaces-mechanics.md` |
| Each frontend's `src/` skeleton + reconciliation | `references/3-app/frontend/app-skeleton.md` |
| `tokens.css`, light/dark, shadcn wiring | `references/3-app/frontend/tokens-setup.md` |
| Styling discipline in feature code | `references/4-feature/styling-discipline.md` |
| `.env` split + `VITE_*` isolation across planes | `references/2-repo/env-and-config/env-precedence.md`, `.../frontend-env-isolation.md` |
| `config.yaml` per service, secrets matrix | `references/2-repo/env-and-config/per-service-config.md`, `.../secrets-matrix.md` |
| `docker/` compose base + `.m.` modifiers, expose tiers | `references/2-repo/runtime/docker-overview.md` |
| `ctl` dispatcher model + commands | `references/2-repo/runtime/script-overview.md`, `.../script-usage.md` |
| `nginx/` route separation (public vs internal edge) | `references/2-repo/deployment/proxy-and-exposure.md` |
| Production serving (workers, migrations-on-deploy) | `references/3-app/backend/serving.md`, `references/2-repo/deployment/production-readiness.md` |
| `.mise.toml` runtime contract | `references/2-repo/runtime/mise.md` |
| Root README + per-service READMEs | `references/2-repo/readme-three-paths.md` |
| `infra/` vs `data/`, engine choice | `references/2-repo/databases-provisioning.md` |
| Recorded-variant table in CLAUDE.md | `references/00_altitude-model.md`, `references/handoffs/claude-folder.md` |

## See also

- `references/5-examples/00_index.md` — how to read the examples; example ↔ layout ↔ variant map
- `references/5-examples/02_canonical-1be-1fe.md` — the flat single-backend/single-frontend baseline this scales up from
- `references/2-repo/layouts/02_multi-app-monorepo.md` — the layout, full scaling spectrum, core-vs-BFF axis
- `references/2-repo/grouping-topology.md` — flat/plane-grouped/hybrid decision (T1), rooting, package scope
- `references/3-app/backend/two-plane-split.md` — the admin/user split decision this example instantiates
