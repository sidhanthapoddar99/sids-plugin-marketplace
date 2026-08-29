# Conventions

Rules that hold across every file and every change. Each one is an audit finding when broken.

## The agent brief

- `AGENTS.md` at the root is the real brief. `CLAUDE.md` is one line: `@AGENTS.md`. Both hosts read the same text.
- `memory/` holds the working rules, one file per rule set. `AGENTS.md` links to it. Read it before any change.
- `AGENTS.md` records every exception to the standard layout under its own heading. An unrecorded exception is a defect.
- Template: `template/AGENTS.md`, `template/memory/00_rules.md`.

## Inside an app

| Rule | Detail |
|---|---|
| Feature folders | Frontend code groups by feature, not by kind: `features/<name>/{components,hooks,api}.ts`, not `components/`, `hooks/` at the top. Shared primitives stay in `components/` and `lib/`. |
| API and pages | A page composes features and calls `lib/api.ts`. A feature never calls `fetch` directly. |
| Types and contracts | The API contract is `@scope/types`, generated from OpenAPI. Backend request/response models (`<domain>/models.py`) are the source. No hand-written mirror. |
| Styling | Utilities from the theme (`bg-bg-1`, `rounded-md`), never `var(--…)` in a component, never a hex value, never an arbitrary value. Tokens change in `tokens.css` only. |
| Caps | A file over 300 lines, a component over 150, a function over 40: split. A feature imported by two features: extract to a package. |
| Extraction | Code two apps need moves to `apps/packages/`. An app never imports from another app. |

## Scope and decoupling

Code is placed by the scope that needs it, and a scope depends only inward. Same rule on both sides.

| Scope | Frontend | Backend |
|---|---|---|
| Product | `apps/packages/` — theme, components, API types | `apps/packages/` — shared Python packages or Rust crates, if any |
| App | `src/lib/`, `src/components/` (app-wide primitives), `src/routes/` | `app/main.py`, `app/config.py`, `app/db.py`, `app/core/` (security, redis, rate limit) |
| Feature / domain | `src/features/<name>/` — its components, hooks, api calls, state | `app/<domain>/` — `models.py`, `repository.py`, `service.py`, `router.py` |
| Unit | one component file, one hook | one function |

Rules:

- **A scope imports only from scopes above it.** A feature imports app primitives and packages. An app primitive never imports a feature. A router calls a service; a service never imports a router.
- **Features do not import each other's internals.** Frontend: two features that need the same thing share it through the app scope or a package. Backend: a domain calls another domain's `service`, never its `repository`. If two are always changed together, they are one.
- **Each layer has one job.** Router: parse, authorise, call, serialise. Service: the rule, and the domain's only public surface. Repository: the query, given a connection; the caller owns the transaction. A page: compose features. A component: render props. No HTTP in a service, no SQL in a router, no `fetch` in a component.
- **Cross the boundary with types, not internals.** A feature exposes an `index.ts`; a service exposes functions over domain objects; a backend exposes schemas that `@scope/types` is generated from. Nobody reaches into another's files.
- **Promote when shared, never before.** A thing moves up one scope when its second consumer appears. A thing used once stays where it is used. The same rule sizes a backend: flat `app/` until the second domain, domain slices until a layer is reused by a second binary, crates after that.
- **State lives at the narrowest scope that needs it.** Component state in the component, feature state in the feature, app state only for what every feature reads (session, theme).

These rules are the input to a conformance check. When one is broken a second time, write the check; see "Conformance" in `06_testing.md`.

## Naming

- App folders take the role, not the stack: `api/`, `engine/`, `dashboard/`, `cli/`. Suffix when two share a role: `api-admin/`, `api-platform/`.
- Package folders take what they export: `ui/`, `styles/`, `types/`, `tsconfig/`.
- Scripts take the verb: `scripts/db/migrate.sh` is `ctl migrate`.
- Compose files: `compose.<role>.yaml`; modifiers `compose.m.<name>.yaml`. Never a bare `compose.yaml`.
- Env keys: `<SERVICE>_<THING>`: `POSTGRES_HOST`, `WEB_APP_PREFIX`, `ENGINE_URL`.
- Files that must be sourced, not executed: leading underscore, `_lib.sh`.

## Residue

A restructure is done only when nothing describes the old tree. Delete or move; do not keep "just in case". Git history is the backup.

| Residue | Rule |
|---|---|
| Stale self-description | `README.md`, `AGENTS.md` or docs naming folders, paths or commands that no longer exist. Fix in the same change that moved them. |
| Graveyard folders | `old/`, `backup/`, `<thing>-v1/`, `*-old/`. Delete. |
| Retired duplicates | Two config systems, two docs sites, two tools for one job. Finish the migration and delete the loser. |
| Committed archives | Datasets, dumps, model weights, zips beside code. Move to `data/` or external storage. |
| Loose worktrees and scratch checkouts | Inside the repo or beside it. Keep them under an ignored path or outside the project folder. |
| Scaffolded emptiness | An empty `docker/`, `infra/`, `docs/`, `tests/`, `logs/` "for later". A folder exists only when used. |

## Tripwires

Each of these means a rule above was broken somewhere else. Find that place.

| Seen | Broken rule |
|---|---|
| `VITE_API_URL`, `NEXT_PUBLIC_API_URL` | single origin (`03_setup.md`) |
| CORS middleware for our own frontend | single origin |
| `source .env*` in a script | skip-if-set loading (`02_env.md`) |
| `os.environ[...]` outside `config.py` | one loader |
| a password in `config.yaml` | secrets in `.env.secrets` only |
| a `VITE_*` key in `.env.proxy`, or an env file inside a frontend | a frontend has no env file; its prefix comes from `.env.proxy` |
| `alembic upgrade` in a Dockerfile `CMD` or app startup | migrations are an explicit step |
| `ports:` in `compose.base.yaml` | exposure by modifier only |
| `../` in a compose file | root-relative paths |
| `package.json` at the root or in `apps/` | no workspace |
| a second nginx service | the `web` image is the edge |
| `docker compose -f` in a README | `ctl` is the entrypoint |
| a `tests/` folder at the root | tests live with the app |

## Audit order

When asked to audit a repo, check in this order and stop at the first failing layer. A broken lower layer makes the upper ones meaningless.

1. Layout: the tree, root hygiene, residue (`01_layout.md`)
2. Env: the five files, secrets, precedence (`02_env.md`)
3. Setup: origin, prefixes, compose shape (`03_setup.md`, `05_ctl.md`)
4. Stack: choices against the list (`04_stack.md`)
5. Testing: placement and the gate (`06_testing.md`)
6. This file.

Report findings as a table: file, rule broken, fix. `ctl check` covers the mechanical part; run it first.
