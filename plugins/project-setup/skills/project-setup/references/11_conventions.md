# Conventions — what holds everywhere

Rules that hold across every file and every change. Each one is an audit finding when broken. Frontend-only rules: `05_frontend.md`. Backend-only rules: `06_backend.md`.

## The agent brief

`AGENTS.md` at the root is the real brief. `CLAUDE.md` is one line: `@AGENTS.md`. Both hosts read the same text. `memory/` holds the working rules, one file per rule set, flat kebab-case, with a `README.md` index; `AGENTS.md` imports them with `@memory/<file>.md`. Template: `template/AGENTS.md`, `template/memory/`.

The brief is a contract, not a welcome note. Skills are not always loaded; the brief is. Every "record it in `AGENTS.md`" in these pages lands in one of these sections:

| Section | Holds |
|---|---|
| Recorded choices | One table: layout shape (single frontend / group), backend role, identity planes, migration style, theme modes, protection tier, ladder rungs, source-only or published. Audits compare the repo against this table, not against the canon. A chosen variant is not drift. |
| Skeletons | The resolved tree for this repo: which domains, which features, which packages. Names, not placeholders. |
| Tripwires | The numbers below, plus any this repo tightened. Crossing one obligates the restructure **or a one-line recorded deferral here** (what, until when). Silent growth past a tripwire is the failure this section exists to catch. |
| Styling | The typography allowlist and the emphasis weight, resolved; the precedence rule over `frontend-design` (`05_frontend.md`). |
| Exceptions | Every departure from the standard layout, with its reason. An unrecorded exception is a defect. |
| Stack | The table of picks with versions, and the reason for any addition to `04_stack.md`. |
| Commands | The `ctl` surface this repo actually has. Matches `ctl --help`, or the brief is stale. |
| Escalation | "For any structural decision this brief does not cover, load the `project-setup` skill. Do not improvise a pattern inline." |

In a multi-repo product each brief states the repo's one-sentence role and names its siblings; repo names are `<product>-<role>`, the prefix chosen at the first split.

## Documentation points at code, never the reverse

Docs, plans, tracker issues and skill pages name the files, functions and lines they describe. Code does not name them back. A comment in code never says "see plan 12", "subtask 3.2", "`10_testing.md`" or "the docs explain this". The code knows nothing about the documentation.

Why: documentation moves, renumbers and gets deleted; a tracker issue closes; a skill page is renamed. A code comment that names one goes stale on the next reorganisation and nobody notices, because no test reads comments. The reverse link is cheap to keep: a doc that names `scripts/gate/_gate.sh` is checked every time someone opens it.

| Where | Rule |
|---|---|
| Code, scripts, compose, config, tests | Comments explain the code in front of them: what it holds, the rule it enforces, why it is shaped this way. No path to a doc, plan, issue or skill page. No private repo names or home-directory paths. |
| `README.md`, `AGENTS.md`, `memory/` | The one exception. They are the entry doors and may point at `docs/`, the tracker and the skill. |
| `docs/`, the tracker, skill references | Point at code by path. The pointer is the doc's job. |

A rule a comment wants to cite is written into the comment itself, in one sentence.

## Scope and decoupling

Code is placed by the scope that needs it, and a scope depends only inward. Same rule on both sides.

| Scope | Frontend | Backend |
|---|---|---|
| Product | `apps/packages/` — theme, components, API types | `apps/packages/` — shared Python packages or Rust crates, if any |
| App | `src/lib/`, `src/components/ui/`, `src/layout/`, `src/stores/` | `app/main.py`, `app/config.py`, `app/db.py`, `app/core/` |
| Domain | `src/features/<name>/`, `src/api/<domain>.ts` | `app/<domain>/` — `models`, `repository`, `service`, `router` |
| Unit | one component file, one hook | one function |

- **A scope imports only from scopes above it.** A feature imports app primitives and packages. An app primitive never imports a feature. A router calls a service; a service never imports a router.
- **Features do not import each other's internals.** Frontend: through `index.ts`, or share through the app scope or a package. Backend: a domain calls another domain's `service`, never its `repository`. If two are always changed together, they are one.
- **Each layer has one job.** Router: parse, authorise, call, serialise. Service: the rule, and the domain's only public surface. Repository: the query, given a connection. A page: compose features. A component: render props. No HTTP in a service, no SQL in a router, no `fetch` in a component.
- **Cross the boundary with types, not internals.** A feature exposes `index.ts`; a service exposes functions over domain objects; a backend exposes schemas that `@scope/types` is generated from. Never import a DTO across domains to reuse a shape; duplicate it.
- **Promote when shared, never before.** A thing moves up one scope when its second consumer appears. The same rule sizes a backend: flat `app/` until the second domain, domain slices until a layer is reused by a second binary, crates after that.
- **State lives at the narrowest scope that needs it.** Component state in the component, feature state in the feature, app state only for what every feature reads (session, theme).
- **Providers of one kind are adapters.** `modules/<provider>/` behind one `base` contract, one output shape, engine code that never names a provider.

These rules are the input to a conformance check. When one is broken a second time, write the check; see "Conformance" in `10_testing.md`.

## Caps and extraction

| Rule | Number | Detail |
|---|---|---|
| File | 300 lines soft, 500 hard | Source, tests, components. Not generated code, vendored code, lock files or data fixtures. Relaxed only with a comment at the top saying why, and a ledger row in the conformance test. |
| Function | 40 lines | Split by responsibility. |
| Component | 150 lines; page 50 | `05_frontend.md`. |
| Feature folder | ~10 files | Subdivide inside the folder, by the axis that carries the real seam. |
| Domains per backend | ~8–10 flat | Or when the domain model settles, whichever first. Below that a domain layer is ceremony. |
| Logic | rule of three | One use inline; two, duplicate (they may diverge); three, extract and name it for what it means. Extract on first use when the pattern is non-obvious, dangerous (crypto, untrusted input), or owned by another layer. Framework boilerplate is not duplication. |
| Styling | rule of two | The same utility combination twice → a primitive variant. |

No catch-all folders: `helpers/`, `utils/`, `common/`, a global `types.ts`. `auth/helpers.py` is auth-scoped and fine; `shared/` exists only when three or more features need it. Split vertically by feature, never horizontally by kind.

## Naming

- App folders take the role, not the stack: `api/`, `engine/`, `dashboard/`, `cli/`. Suffix when two share a role: `api-admin/`, `api-platform/`.
- Domains are nouns of ownership, never activities or nav labels (`06_backend.md`).
- Package folders take what they export: `ui/`, `types/`, `tsconfig/`.
- Scripts take the verb: `scripts/db/migrate.sh` is `ctl migrate`.
- Compose files: `compose.<role>.yaml`; modifiers `compose.m.<name>.yaml`. Never a bare `compose.yaml`.
- Env keys: `<SERVICE>_<THING>`: `POSTGRES_HOST`, `WEB_APP_PREFIX`, `ENGINE_URL`.
- Files that must be sourced, not executed: leading underscore, `_lib.sh`.
- A helper is named for what it means (`can_manage`), never for what it does mechanically (`process_data`).

## Residue

A restructure is done only when nothing describes the old tree. Delete or move; do not keep "just in case". Git history is the backup. Reconcile structure in the same milestone the domain model settles; batch moves into a window where churn already happens.

| Residue | Rule |
|---|---|
| Stale self-description | `README.md`, `AGENTS.md` or docs naming folders, paths or commands that no longer exist. Fix in the same change that moved them. |
| Graveyard folders | `old/`, `backup/`, `<thing>-v1/`, `*-old/`. Delete. A frozen legacy package kept beside its replacement is the one exception: excluded from lint and every gate, README first line says frozen, no tsconfig or alias routes into it. |
| Retired duplicates | Two config systems, two docs sites, two tools for one job. Finish the migration and delete the loser. |
| Committed archives | Datasets, dumps, model weights, zips beside code. Move to `data/` or external storage. |
| Loose worktrees and scratch checkouts | Inside the repo or beside it. Keep them under an ignored path or outside the project folder. |
| Scaffolded emptiness | An empty `docker/`, `docs/`, `tests/`, `logs/` "for later". A folder exists only when used. |
| Symlinks between apps; repo scripts inside an app | Neither. Share through a package; orchestrate through `ctl`. |

## Tripwires

Each of these means a rule was broken somewhere else. Find that place.

| Seen | Broken rule |
|---|---|
| `VITE_API_URL`, `NEXT_PUBLIC_API_URL` | single origin (`03_routing.md`) |
| CORS middleware for our own frontend | single origin |
| `source .env*` in a script | skip-if-set loading (`02_env.md`) |
| `os.environ[...]` outside `config.py` | one loader |
| a password in `config.yaml` | secrets in `.env.secrets` only |
| a `VITE_*` key in `.env.proxy`, or an env file inside a frontend | a frontend has no env file; its prefix comes from `.env.proxy` |
| `alembic upgrade` or `create_all()` in a Dockerfile `CMD` or app startup | migrations are an explicit step (`06_backend.md`) |
| `ports:` in `compose.base.yaml` | exposure by modifier only (`08_ctl.md`) |
| `../` in a compose file | root-relative paths |
| `package.json` at the root or in `apps/` | no workspace (`01_layout.md`) |
| a second nginx service | the `web` image is the edge |
| `docker compose -f` in a README | `ctl` is the entrypoint |
| a `tests/` folder at the root | tests live with the app (`10_testing.md`) |
| `text-[13px]`, a hex in a `.tsx`, `var(--…)` in JSX | tokens and the stock scale (`05_frontend.md`) |
| `fetch(` outside `src/api/` | the api layer |
| a domain named `build/`, `sync/`, `ingest/` | ownership nouns (`06_backend.md`) |
| `uvicorn --reload` in a Dockerfile | production serving (`06_backend.md`) |
| a tripwire crossed with no deferral in `AGENTS.md` | the brief is the contract |
| a code comment naming a doc page, plan, issue or skill file | documentation points at code, never the reverse |

## Audit order

When asked to audit a repo, check in this order and stop at the first failing layer. A broken lower layer makes the upper ones meaningless.

1. Layout: the tree, root hygiene, residue (`01_layout.md`)
2. Env: the five files, secrets, precedence (`02_env.md`)
3. Routing: origin, prefixes, compose shape (`03_routing.md`, `08_ctl.md`)
4. Stack: choices against the list and against the recorded choices (`04_stack.md`)
5. Frontend and backend internals (`05_frontend.md`, `06_backend.md`)
6. Security floor (`07_security.md`)
7. Production settings (`09_production.md`)
8. Testing: placement and the gate (`10_testing.md`)
9. This file.

Report findings as a table: file, rule broken, fix. `ctl check` covers the mechanical part; run it first. A recorded choice or a recorded deferral is not a finding.
