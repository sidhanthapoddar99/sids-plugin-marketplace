# Conventions — what holds everywhere

Rules that hold across every file and every change. Each one is an audit finding when broken. Frontend-only rules: `05_frontend.md`. Backend-only rules: `06_backend.md`.

## The agent brief

`AGENTS.md` at the root is the brief. The working rules are its `Working rules` section. Template: `template/AGENTS.md`. Add-on: `additional-template/memory/`, for a project whose rule sets the user wants as separate files.

Every `AGENTS.md` has a `CLAUDE.md` beside it whose whole content is `@AGENTS.md`, because Claude Code reads `CLAUDE.md` and loads `AGENTS.md` only through that import, while Codex reads `AGENTS.md`. The import gives both hosts one text. A `CLAUDE.md` is a plain file, not a symlink, because a symlink breaks on a checkout that does not keep links.

What a brief holds, so it stays short enough to be read whole on every session:

- Current facts only: what to do and why. The history of a rule is in git, and a plan, a deferral or a known gap is in the tracker, because a brief loads every turn and old text costs every turn.
- A rule once. A rule that holds in every folder lives in the root brief. A nested `AGENTS.md` exists only for a folder whose rules differ, and holds only those rules. Detail a task needs only sometimes goes in the folder's `README.md`, which the agent opens when it works there.
- A rule a check can enforce goes into `ctl check` or a test, and the brief keeps one line that names the check. A rule an agent must remember drifts; a rule `ctl` runs does not.

`ctl check` enforces the size: under 200 lines per brief, at most 32 KiB for all briefs together (Codex stops reading past that), no `YYYY-MM-DD` date in a brief, and the `CLAUDE.md` beside each one (`08_ctl.md` § `ctl check`).

For an existing target repo, inspect `CLAUDE.md` at its root and in every directory from the root to each path being worked on. Tell the user which files you found. A file that holds only `@AGENTS.md` is already right. Move any other content into the `AGENTS.md` beside it, under the rules above, then write the `CLAUDE.md` as `@AGENTS.md`. If an instruction conflicts with `AGENTS.md`, or its meaning or destination is unclear, ask the user before replacing that file. During a read-only audit or a one-question consultation, report the needed migration without changing files.

The brief is a contract, not a welcome note. Skills are not always loaded; the brief is. Every "record it in `AGENTS.md`" in these pages lands in one of these sections:

| Section | Holds |
|---|---|
| Recorded choices | One table: layout shape (single frontend / group), backend role, identity planes, migration style, theme modes, protection tier, ladder rungs, source-only or published. Audits compare the repo against this table, not against the canon. A chosen variant is not drift. |
| Skeletons | The resolved tree for this repo: which domains, which modules, which packages. Names, not placeholders. |
| Tripwires | The numbers below, plus any this repo tightened. Crossing one obligates the restructure **or a deferral recorded in the tracker** (what, until when). Silent growth past a tripwire is the failure this section exists to catch. |
| Styling | The typography allowlist and the emphasis weight, resolved; the precedence rule over `frontend-design` (`05_frontend.md`). |
| Exceptions | Every departure from the standard layout, with its reason. An unrecorded exception is a defect. |
| Stack | The table of picks with versions, and the reason for any addition to `04_stack.md`. |
| Commands | The `ctl` surface this repo actually has. Matches `ctl --help`, or the brief is stale. |
| Escalation | "For any structural decision this brief does not cover, load the `project-setup` skill. Do not improvise a pattern inline." |

In a multi-repo product each brief states the repo's one-sentence role and names its siblings; repo names are `<product>-<role>`, the prefix chosen at the first split.

## Documentation points at code, never the reverse

Docs, plans, tracker issues and skill pages name the files, functions and lines they describe. Code does not name them back. A comment in code never says "see plan 12", "subtask 3.2", "`10b_static-checks.md`" or "the docs explain this". The code knows nothing about the documentation.

Why: documentation moves, renumbers and gets deleted; a tracker issue closes; a skill page is renamed. A code comment that names one goes stale on the next reorganisation and nobody notices, because no test reads comments. The reverse link is cheap to keep: a doc that names `scripts/gate/_gate.sh` is checked every time someone opens it.

| Where | Rule |
|---|---|
| Code, scripts, compose, config, tests | Comments explain the code in front of them: what it holds, the rule it enforces, why it is shaped this way. No path to a doc, plan, issue or skill page. No private repo names or home-directory paths. |
| `README.md`, `AGENTS.md`, `memory/` | The one exception. They are the entry doors and may point at `docs/`, the tracker and the skill. |
| `docs/`, the tracker, skill references | Point at code by path. The pointer is the doc's job. |

A rule a comment wants to cite is written into the comment itself, in one sentence.

## A missing tool is installed, never coded around

A script that needs a tool, such as `jq`, calls `require_tools jq`, and `.mise.toml` declares the tool so `ctl setup` installs it. When the tool is missing, install it. Never replace it with code that avoids it, such as a hand-written JSON parser or a branch that skips the step when `command -v` fails, because the callers depend on what the tool does and no test notices the loss. A tool that mise cannot provide is listed under Prerequisites in the root `README.md`, with its install command. `scripts/common/_tools.sh` names the install step in every missing-tool message, including a mise shim that has no version for the repo.

## Scope and decoupling

Code is placed by the scope that needs it, and a scope depends only inward. Same rule on both sides.

| Scope | Frontend | Backend |
|---|---|---|
| Product | `apps/packages/` — theme, components, API types | `apps/packages/` — shared Python packages or Rust crates, if any |
| App | `src/lib/`, `src/components/`, `src/layout/`, the routing folder | `app/main.py`, `app/config.py`, `app/db.py`, `app/core/` |
| Domain | `src/modules/<name>/`, `src/lib/api/<domain>.ts` | `app/<domain>/` — `models`, `repository`, `service`, `router` |
| Unit | one component file, one function | one function |

- **A scope imports only from scopes above it.** A module imports app components and packages. An app component never imports a module. A router calls a service; a service never imports a router.
- **Modules do not import each other.** Frontend: a module never imports a sibling module; a shared piece moves to the app scope or a package. Backend: a domain calls another domain's `service`, never its `repository`. If two are always changed together, they are one.
- **Each layer has one job.** Backend layers: `06_backend.md` § Domain slices. Frontend: a route picks a layout and mounts a module, a module assembles a screen, a component renders props. No HTTP in a service, no SQL in a router, no `fetch` in a component, because a layer with two jobs cannot be tested alone.
- **Cross the boundary with types, not internals.** A module exposes `index.tsx`; a service exposes functions over domain objects; a backend exposes schemas that `@scope/types` is generated from. Never import a DTO across domains to reuse a shape; duplicate it, because a shared DTO couples two domains' releases and a field change in one breaks the other.
- **Promote when shared, never before.** A thing moves up one scope when its second consumer appears, because a premature package is a second manifest to keep green for nothing. The same rule sizes a backend: flat `app/` until the second domain; domain slices until a layer is reused by a second binary; a cargo workspace of crates after that, which applies to Rust only.
- **State lives at the narrowest scope that needs it.** Component state in the component, module state in the module, app state only for what every module reads (session, theme). Wider state re-renders more than it needs to.
- **Providers of one kind are adapters.** `06_backend.md` § Domain slices holds the rule and its reason.

These rules are the input to a lint rule. When one is broken a second time, write the rule; see "Layer rules are lint config" in `10b_static-checks.md`.

## Caps and extraction

| Rule | Number | Detail |
|---|---|---|
| File | 300 lines soft, 500 hard | Source, tests, components. Not generated code, vendored code, lock files or data fixtures. Past 300 a file holds two things; past 500 nobody reads it whole. Relaxed only with a comment at the top saying why, and an inline lint-ignore on that file. |
| Function | 40 lines | Split by responsibility, because a longer one carries a second responsibility. |
| Component | 150 lines; page 50 | A page is a route, so it composes; a component past 150 lines holds a second component. This row is the home; `05_frontend.md` points here. |
| Feature folder | ~10 files | Subdivide inside the folder, along the axis the files change on together. Ten files is where a listing stops fitting on one screen. |
| Domains per backend | ~8–10 flat | Or when the domain model settles, whichever first. Below that a domain layer is ceremony. |
| Logic | rule of three | One use inline; two, duplicate (they may diverge); three, extract and name it for what it means. Extract on first use when the pattern is non-obvious, dangerous (crypto, untrusted input), or owned by another layer. Framework boilerplate is not duplication. |
| Styling | rule of two | The same utility combination twice → a primitive variant. |

No catch-all folders: `helpers/`, `utils/`, `common/`, a global `types.ts`. `auth/helpers.py` is auth-scoped and fine; `shared/` exists only when three or more modules need it. Split vertically by module, never horizontally by kind.

## Naming

This section is the home of every folder name; `01_layout.md` points here. A name says what a thing is for, never what it is built with, because the stack changes and the role does not.

- App folders take the role, not the stack: `api/`, `engine/`, `dashboard/`, `cli/`. Suffix when two share a role: `api-admin/`, `api-platform/`. The template's `example-api-python` names label the examples; a real repo renames them at bootstrap.
- The static-frontend group takes a name that says it is a group: `multi-web-app/`. Its children take the surface: `app/`, `landing/`, `docs/`, `admin/`.
- Domains are nouns of ownership, never activities or nav labels (`06_backend.md`).
- Package folders take what they export: `ui/`, `types/`, `tsconfig/`; later `services/`, `hooks/` (`05_frontend.md`).
- Scripts take the verb: `scripts/db/migrate.sh` is `ctl db migrate`.
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
| a password in `config.yaml` | secrets in `.env` only |
| a `VITE_*` key in `.env`, or an env file inside a frontend | a frontend has no env file; its prefix comes from `.env` |
| `flyway migrate` or `create_all()` in a Dockerfile `CMD` or app startup | migrations are an explicit step (`06_backend.md`) |
| `ports:` in any config `compose.<name>.yaml` | exposure by modifier only (`08a_ctl_docker.md`) |
| `../` in a compose file | root-relative paths |
| `package.json` at the root or in `apps/` | no workspace (`01_layout.md`) |
| a second nginx service | the `web` image is the edge |
| `docker compose -f` in a README | `ctl` is the entrypoint |
| a `tests/` folder at the root | tests live with the app (`10c_dynamic-tests.md`) |
| `text-[13px]`, a hex in a `.tsx`, `var(--…)` in JSX | tokens and the stock scale (`05_frontend.md`) |
| `fetch(` outside `src/lib/api/` | the api layer (`05_frontend.md`) |
| `src/features/`, `src/pages/` in a Vite app, a module importing a sibling | the folder shape (`05_frontend.md`) |
| a domain named `build/`, `sync/`, `ingest/` | ownership nouns (`06_backend.md`) |
| `uvicorn --reload` in a Dockerfile | production serving (`06_backend.md`) |
| a tripwire crossed with no deferral in the tracker | the brief is the contract |
| a brief that tells the history of a rule, or a nested `AGENTS.md` that repeats the root one | the brief holds current facts, once |
| a code comment naming a doc page, plan, issue or skill file | documentation points at code, never the reverse |
| `command -v <tool>` followed by another way to do the tool's job | a missing tool is installed, never coded around |
| a `ctl` that does not source `scripts/common/_lib.sh`, or a helper in `scripts/common/` that differs from the template | `ctl` is a copy of the template (`08_ctl.md` § Copy and verify) |

## Audit order

Check the layers in this order and report every one of them, lowest first, because a broken lower layer often explains an upper finding and the reader fixes in this order. The audit workflow itself, `ctl check` first and the report shape, is in `SKILL.md` § Auditing.

1. Layout: the tree, root hygiene, residue (`01_layout.md`)
2. Env: the five files, secrets, precedence (`02_env.md`)
3. Routing: origin, prefixes, compose shape (`03_routing.md`, `08_ctl.md`)
4. Stack: choices against the list and against the recorded choices (`04_stack.md`)
5. Frontend and backend internals (`05_frontend.md`, `06_backend.md`)
6. Security floor (`07_security.md`)
7. Production settings (`09_production.md`)
8. Verification: the ladder and the static rungs (`10b_static-checks.md`), test placement (`10c_dynamic-tests.md`), the review passes (`10a_review.md`)
9. This file.
