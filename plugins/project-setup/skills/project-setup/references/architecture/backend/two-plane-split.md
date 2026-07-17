# Two-plane split — separate admin (operator) and user (platform) backends

Some products have two kinds of humans: **end-users** of the platform and **operators** who administer it. The structural question is whether that's one backend with role-gated routes or two backends — and, if two, how they share one database without coupling. This reference owns that decision and its mechanics.

## When to split — the decision

Split admin (operator) and user (platform) into **separate backends** when they need **different security postures**. Any ONE of these is sufficient:

| Signal | What it means |
|---|---|
| **Separate identity namespace** | Operators get their own credentials table, their own session/refresh-token namespace, no third-party OAuth, and bootstrap via a break-glass CLI — never a public signup flow |
| **Independent exposure** | The admin surface can stay off the public edge entirely (internal network, VPN, separate expose tier) while the platform is public |
| **Independent deploy cadence** | Admin tooling ships on its own schedule without redeploying the user-facing service |

A styling difference or a different nav structure is **NOT** a reason to split — that's one backend with role-gated routes and one frontend (or two frontends over the same backend).

Ask it as an identity question, not a count question: **"does any surface need a separate identity/security plane (operator/admin vs end-user)?"** The backend count falls out of the answer instead of being guessed.

## One database is the normal case, not a smell

Two backends over one Postgres works — under strict ownership:

- **Every fact kind has exactly one writing owner.** For each table (or column family), one backend writes it; the other reads it. Document the ownership table.
- **The schema is the only shared contract.** No shared ORM/models package between the backends — each declares its **own DTOs** against the schema (see the DTO rules in `references/architecture/modularity/domain-grouping-tripwire.md`).
- Coordination beyond the schema goes over a transport — Postgres LISTEN/NOTIFY, Redis streams, HTTP — never concurrent writes to the same tables.

## Migrations get a neutral owner: a standalone `apps/db`

With two backends over one database, the DDL owner should be **neither of them**. Making one backend the owner creates a false hierarchy (the "owning" backend looks authoritative over shared tables) and couples schema changes to that app's deploy cadence. Instead:

```
apps/
├── db/                      # the migrations app — sole DDL owner
│   ├── pyproject.toml       # alembic + driver only; imports NO backend code
│   ├── alembic.ini
│   └── alembic/
│       └── versions/        # plain Alembic, or the raw-SQL three-file pattern
├── api-platform/            # pure consumer of the schema
└── api-admin/               # pure consumer of the schema
```

- `apps/db` imports no backend code and no backend imports it — the schema contract stays neutral.
- The raw-SQL three-file pattern (`references/architecture/backend/alembic-with-raw-sql.md`) fits naturally here: the `.sql` files are readable by every consumer regardless of language.
- Migrations run **only via the dispatcher** — `ctl migrate {up|down|new|status}` targets `apps/db` — never on any backend's boot. Two backends racing entrypoint migrations is the failure this prevents.
- **Scope note:** for the **single-backend** case, the existing default stands — that backend owns its migrations, entrypoint-migrates-on-deploy is fine (`references/architecture/backend/alembic-default.md`). The neutral owner is the two-backend escalation.

## Frontends: two planes, one workspace

The identity planes are separate; the **visual language is not**. Both frontends share the workspace and its packages — `ui`, `styles`/tokens, `types`, auth service *shapes* — even though sessions never cross planes:

- The two frontends pair naturally with the **plane-grouped `apps/` topology** (`apps/client/{platform,admin}` — see the grouping variants in `references/repo-setup/layouts/02_multi-app-monorepo.md`).
- Backend secrets never enter either frontend's env scope (`references/repo-setup/env-and-config/frontend-env-isolation.md`) — doubly load-bearing here, since the admin plane's URLs/keys must not leak into the public bundle.
- Exposure follows the split: the admin frontend + `api-admin` can bind to an internal expose tier while the platform pair is public — see the expose tiers in `references/repo-setup/runtime/docker-overview.md` and route separation in `references/architecture/frontend/vite-proxy-nginx-pair.md`.

## Audit checks

- Two backends + a shared models/ORM package between them = red finding (contract coupling).
- Two backends where one owns DDL over shared tables = finding — propose the `apps/db` neutral owner.
- Any backend running migrations on boot in a two-backend repo = finding.
- Admin identity reachable through the public signup/OAuth flow = red finding (security posture).
- Two frontends duplicating ui/tokens instead of sharing the workspace packages = finding.

## Anti-patterns

- Splitting backends because the admin UI *looks* different — that's a frontend concern; split on security posture only.
- A shared `models` package "to avoid duplication" — the duplication IS the decoupling; the schema is the single contract.
- Operator accounts as a `role` column on the public users table when the split was chosen — separate plane means separate identity namespace.
- The admin backend proxying the platform backend for reads it could make against the schema — adds a hop and a false dependency.
- Two DDL owners, or migrations racing on boot — one neutral owner, run explicitly.

## See also

- `references/architecture/backend/alembic-default.md`, `alembic-with-raw-sql.md` — the migration mechanics `apps/db` runs
- `references/architecture/modularity/domain-grouping-tripwire.md` — DTO ownership rules both backends follow
- `references/repo-setup/layouts/02_multi-app-monorepo.md` — the grouping topology this pairs with
- `references/repo-setup/env-and-config/` — env split + frontend isolation
- `references/levels/02_repo.md` — the repo-level charter that routes here
