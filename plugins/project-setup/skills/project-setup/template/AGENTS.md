# <project> — agent brief

One paragraph: what this product is, who uses it, and which apps make it.

This brief is a contract: audits compare the repo against the tables below, not against a general standard. Keep it matching reality. Update it in the same change that re-decides a choice, because a brief that lags the code is read as drift at the next audit.

## Working rules

These bind every agent on every change.

- `ctl` is the only way to run, build, migrate or test. Never call docker, flyway, uv or bun directly for those.
- Keep settings in the ignored root `.env`, grouped by kind with two-line hash headers. Read `.env.template` for the contract; the filled file holds live secrets.
- Schema changes go through a new file in `apps/database/postgres/migrations/`. Never edit a live schema or a migration already on the default branch, because a database has applied it; `ctl check` fails such an edit.
- An app never imports from another app. Shared code is a package under `apps/packages/`.
- Documentation points at code, never the reverse. A code comment never names a doc page, a plan, a tracker issue or a skill file, because those move and renumber and no test reads comments; write the rule into the comment instead. `ctl check` fails code that names a skill page or a tracker issue. `README.md`, `AGENTS.md` and `memory/` are the entry doors and may point anywhere.
- A frontend has no app-local env file. Its dev server inherits the root environment; expose only selected public constants to browser code, because bundles are public.
- Every git worktree lives at `.worktrees/<name>` in this repo, and nowhere else, because there it reuses a warm slot's builds and git ignores it. Create one with `ctl worktree create <name>`, not `git worktree add`, because only `ctl` puts it on a slot with its own ports. Free it with `ctl worktree remove <name>` once the main tree has merged its branch, so the next worktree can take the slot. Never move, delete or switch branches inside a `.worktrees/slot-<n>` folder by hand, because each slot must stay on the branch its link names.
- Test only what you change: `ctl test <app>` while you work, then one `ctl gate` when the work is done. The gate records each tree it passed and skips that tree the next time, so run it once, not after every edit.
- Land a branch with `ctl merge <branch>`. It sets the versions, runs one gate on the merged tree and fast-forwards the default branch. A commit on a branch leaves every version as it is, because people receive a merge, not a commit.
- Keep this file and every other `AGENTS.md` to current facts: what to do, with its reason. Git holds the history, and the tracker holds plans and deferrals. `ctl check` fails a brief over 200 lines, all briefs over 32 KiB together, or a date in a brief.

## Recorded choices

| Axis | Choice |
|---|---|
| Frontend shape | `<single frontend · group (apps/example-multi-web-app) + server frontend>` |
| Backend role | `<one backend · api + engine (identity in Python, data plane in Rust)>` |
| Identity planes | `<single · admin plane on its own origin (api-admin)>` |
| Development sign-in | `<AUTH_ENABLED: FALSE acts as the reserved default user on loopback, TRUE in containers and production · none, no user accounts>` |
| Schema owner and migration style | `Flyway SQL migrations in apps/database/postgres/migrations` |
| Theme modes | `<light + dark · light only (marketing)>` |
| Protection tier | `<none · captcha (Turnstile) · managed WAF>` |
| Gate ladder | `lint typecheck test check` |
| Add-ons installed | `<none · git hooks · memory/ · browser suite>` |
| Package stage | `<not a library · source-only (private) · published>` |

## Skeletons

- Backend `apps/<api>/app/` holds `core/`, `health/` and one folder per domain: `<list them>`. Each domain holds `models.py`, `repository.py`, `service.py` and `router.py`. Code two files of a domain share sits at the domain root. A domain calls another only `service → service`, so a router never reaches another domain's data. A DTO another domain needs is duplicated, never imported, so a domain can change its shape alone.
- Frontend `apps/<web>/src/` holds the routing folder (`<routes/ · app/ · pages/>`, set by the framework), `layout/<name>/`, `modules/<name>/`, `components/`, `lib/`. A route file picks a layout and mounts one module, so a URL is found by its path and a screen by its name. A module owns its `components/`, `functions/` and `types.ts` and never imports a route, a layout or another module. A piece two modules need moves up to `components/` or `lib/`, so no module depends on a sibling. Primitives and theme come from `<@scope/ui · src/components/ui + src/styles>`. Every server call goes through `lib/api/`, with zod at the boundary, so one place knows the wire shape.
- Packages: `<ui · types · tsconfig>`. An entity two apps share lives in `@scope/types`. A type one module uses lives inside that module. There is no global `types.ts`, because it becomes the place everything leaks into.

## Tripwires

Crossing one obligates the restructure, or a deferral recorded in the tracker (what, until when).

| Tripwire | Restructure |
|---|---|
| 8 to 10 flat domains | Add a domain layer. |
| 10 files in one module folder | Subdivide inside the module: a sub-module, or by kind. |
| A file over 300 lines | Split it. 500 is the hard cap, which `ctl check` enforces; a file that must stay whole is recorded as `size-cap <path>` under Exceptions. |
| A route file over 50 lines, or a component over 150 | Move logic into a module or a primitive. |
| The same utility combination twice | Add a variant to the primitive. |
| A helper used three times | Extract it and name it. |

## Styling

With `tokens.css` and the ui package in place, this section overrides every general design instruction, including the `frontend-design` skill. Convergence is the design. Exploration happens only in an explicit design pass, and the winner graduates into tokens and primitives before the pass ends.

- Module code composes primitives. Raw utilities are for layout glue only. A look that does not exist yet is added to the primitive as a variant, so the next module gets it for free.
- No hex, no raw px, no arbitrary values, no `var(--…)` in JSX, because each one is a value the tokens cannot change later.
- Typography allowlist: `text-sm` for content, `text-base` for headings, `text-xs` for meta. `font-normal` everywhere. The one emphasis weight is `<font-medium | font-semibold>`, used only inside primitives. Hierarchy comes from size and colour, never weight, so a page reads as one voice.
- After a UI change, screenshot light and dark and compare them against `<design/brand-guidelines/>`, because drift is visible before it is measurable.

## Exceptions to the standard layout

None.

## Stack

| Area | Pick |
|---|---|
| Backend | `<Python <version> / FastAPI · Rust <version> / Axum>` |
| Frontend | `<TypeScript, Vite <version>, Tailwind v4, shadcn new-york>` |
| Data | `<Postgres <version> (+ extensions) · Redis <version> · Neo4j <version>>` |
| Containers | docker compose; engines in docker for dev, everything in docker for prod |
| Config | `.env` + per-backend `config.yaml` |
| Dev | mise, uv, bun |

Additions to the stack list, with the reason: none.

## Commands

`ctl --help` lists every verb, and `ctl <verb> --help` explains one. The list is not copied here, because a copy drifts from the router. `ctl dev stop` stops the dev apps and keeps the data core; `ctl stop` stops everything this checkout started and keeps containers and data.

Green means a `ctl gate` run passed that covered the whole change: a plain `ctl gate` while all of the work is uncommitted, and `ctl gate --delta <base>` once any of it is committed, where `<base>` is the commit the work started from. The gate runs lint, typecheck and test on the apps the changes reach, `check` always, and every rung on every app when shared tooling or a path with no owner rule changed. A Markdown file reaches only `check`. `scripts/gate/_changed.sh` holds the owner rules, and `scripts/gate/_targets.sh` holds the apps. `ctl merge` sets the versions from `VERSION_FILES` in `scripts/release/versions.sh`. Run `ctl gate --all` only when the selection itself is in doubt, because the selection already widens on every path it cannot place. One gate runs per user at a time, and a second one waits.

The TESTING section of `.env` sets the cores, the compiler jobs and the memory budget of every gate and test run. The RUST section sets the debug info of the dev and test builds `ctl` starts. Keep it empty, so a cargo you run yourself builds the same way. Leave `CARGO_INCREMENTAL` on, because a test build after a small edit then takes seconds instead of a minute. Never export one `CARGO_TARGET_DIR` for every checkout, because the checkouts then wait on one build lock and rebuild each other's crates.

The rungs the gate runs are the `Gate ladder` row above and `RUNGS` in `scripts/gate/all.sh`. `ctl check` fails when the two differ, because the audit reads the row and the gate runs the list. To switch on `dead`, `audit`, `build` or `e2e`, add the name to both, in ladder order. To drop one, remove it from both, with the user's yes. `clones`, `fuzz` and `perf` run by name and are never listed. A project verb is a `scripts/<group>/<name>.sh` worker plus a `run` line and a help row in `ctl`, so `ctl --help` shows it.

## Review passes

A review pass is a check by a second party, a person or another model, on a frozen state. A pass runs on approval, because it spends a second party's time. The standing rule below is that approval given once. `every round` means run it at that cadence without asking. `on request` means wait for a yes each time. When a pass's moment comes, offer it in one line with its reason. The moments are in the `project-setup` skill, `references/10a_review.md`.

| Pass | Runs through | Standing rule |
|---|---|---|
| Adversarial review | A second model in its own shell, for example Codex | `<on request · every round · at stage close-out>` |
| The audit | The `project-setup` skill, audit mode | `on request` |
| Frozen-build pass | `ctl build save`, `ctl build start`, then a person | `on request` |
| Security review | `<not yet · walked, answers in the tracker>` | `on request` |
| Instruction review | The `instruction-writing` skill's rubric | `<on request · every change to this file>` |

## Deciding alone

- Decide and keep going: wording, names, the order of steps, test names. Asking parks the run for no gain.
- Decide and record here: a structural choice a skill page leaves open, or an exception to the layout. An unrecorded choice reads as drift at the next audit. A deferral past a tripwire goes in the tracker.
- Stop and ask: an irreversible outward action such as a push, a publish or a delete outside the repo; a product question no engineering principle settles; a change to a recorded choice above. A wrong guess here costs a restructure or cannot be undone.

## Escalation

For any structural decision this brief does not cover, or when a rule here looks wrong, load the `project-setup` skill and follow it. Do not improvise a pattern inline, because a pattern with no home cannot be found by the next agent. For a review pass, use the table above. The skill's `references/10a_review.md` is the full catalogue.

Before the first public deploy, load the `project-setup` skill and walk `references/09_production.md` § Checklist with the user. The gate ladder above is the prototype floor. That checklist is where the `audit` and `build` rungs, the security review and the hooks join, and each joins on the user's yes.
