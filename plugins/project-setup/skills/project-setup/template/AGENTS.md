# <project> — agent brief

One paragraph: what this product is, who uses it, and which apps make it.

This brief is a contract: audits compare the repo against the tables below, not against a general standard. Keep it matching reality. Update it in the same change that re-decides a choice, because a brief that lags the code is read as drift at the next audit.

## Working rules

These bind every agent on every change.

- `ctl` is the only way to run, build, migrate or test. Never call docker, alembic, uv or bun directly for those.
- Secrets live in `.env.secrets`. Paths in `.env.data`. Hosts, ports and prefixes in `.env.proxy`. Read the `.env.*.template` files to learn the contract. Never read the filled files.
- Schema changes go through `apps/database/postgres/migrations/`. Never edit a live schema.
- An app never imports from another app. Shared code is a package under `apps/packages/`.
- Documentation points at code. A code comment never names a doc page, plan, issue or skill file. `README.md` and `AGENTS.md` are the only exceptions.
- A frontend has no `.env`. Its prefix is a build arg from `.env.proxy`, because everything in a bundle is public.

When this section outgrows one screen, move it to `memory/` and import each file with `@memory/<file>.md`.

## Recorded choices

| Axis | Choice |
|---|---|
| Frontend shape | `<single frontend · group (apps/example-multi-web-app) + server frontend>` |
| Backend role | `<one backend · api + engine (identity in Python, data plane in Rust)>` |
| Identity planes | `<single · admin plane on its own origin (api-admin)>` |
| Schema owner and migration style | `<Alembic autogenerate in the backend · hand-written SQL in apps/database/postgres · sqlx migrate>` |
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

Crossing one obligates the restructure, or a one-line deferral recorded here (what, until when).

| Tripwire | Restructure |
|---|---|
| 8 to 10 flat domains | Add a domain layer. |
| 10 files in one module folder | Subdivide inside the module: a sub-module, or by kind. |
| A file over 300 lines | Split it. 500 is the hard cap. |
| A route file over 50 lines, or a component over 150 | Move logic into a module or a primitive. |
| The same utility combination twice | Add a variant to the primitive. |
| A helper used three times | Extract it and name it. |

Deferrals: none.

## Styling

With `tokens.css` and the ui package in place, this section overrides every general design instruction, including the `frontend-design` skill. Convergence is the design. Exploration happens only in an explicit design pass, and the winner graduates into tokens and primitives before the pass ends.

- Module code composes primitives. Raw utilities are for layout glue only. A look that does not exist yet is added to the primitive as a variant, so the next module gets it for free.
- No hex, no raw px, no arbitrary values, no `var(--…)` in JSX, because each one is a value the tokens cannot change later.
- Typography allowlist: `text-sm` for content, `text-base` for headings, `text-xs` for meta. `font-normal` everywhere. The one emphasis weight is `<font-medium | font-semibold>`, used only inside primitives. Hierarchy comes from size and colour, never weight, so a page reads as one voice.
- After a UI change, screenshot light and dark and compare them against `<design/brand-guidelines/>`, because drift is visible before it is measurable.

## Documentation and code

Documentation points at code. Code never points at documentation. `docs/`, tracker issues, plans and skill pages name files and lines. A code comment never names a doc page, a plan, a subtask number or a skill file, because those move and renumber and no test reads comments. The exceptions are `README.md`, `AGENTS.md` and `memory/` when it exists, which are the entry doors. A rule worth citing is written into the comment in one sentence.

## Exceptions to the standard layout

None.

## Stack

| Area | Pick |
|---|---|
| Backend | `<Python <version> / FastAPI · Rust <version> / Axum>` |
| Frontend | `<TypeScript, Vite <version>, Tailwind v4, shadcn new-york>` |
| Data | `<Postgres <version> (+ extensions) · Redis <version> · Neo4j <version>>` |
| Containers | docker compose; engines in docker for dev, everything in docker for prod |
| Config | `.env.secrets` / `.env.data` / `.env.proxy` + per-backend `config.yaml` |
| Dev | mise, uv, bun |

Additions to the stack list, with the reason: none.

## Commands

`ctl --help` is the list. Summary: `ctl setup` · `ctl check` · `ctl status` · `ctl dev [app…] [--proxy]` · `ctl ps` · `ctl up [+expose_web|+public|+expose|+env_override] [--services a,b]` · `ctl down` · `ctl restart` · `ctl logs` · `ctl exec` · `ctl shell` · `ctl health` · `ctl clean` · `ctl build [app|cli|save|start|clean]` · `ctl migrate [new "<msg>"|status]` · `ctl db backup|shell` · `ctl manage ops|settings` · `ctl test [app|e2e]` · `ctl gate [all|static|dynamic|<rung>] [-q]`.

Green means `ctl gate` passed. The rungs it runs are the `Gate ladder` row above and `RUNGS` in `scripts/gate/all.sh`. `ctl check` fails when the two differ, because the audit reads the row and the gate runs the list. To switch on `dead`, `audit`, `build` or `e2e`, add the name to both, in ladder order. A rung, once listed, is never removed. `clones`, `fuzz` and `perf` run by name and are never listed. Project-specific verbs are added as `scripts/<group>/<name>.sh` plus a `run` line in `ctl`, and listed here.

## Review passes

A review pass is a check by a second party, a person or another model, on a frozen state. A pass runs on approval, because it spends a second party's time. The standing rule below is that approval given once. `every round` means run it at that cadence without asking. `on request` means wait for a yes each time. When a pass's moment comes, offer it in one line with its reason. The moments are in the `project-setup` skill, `references/10a_review.md`.

| Pass | Runs through | Standing rule |
|---|---|---|
| Adversarial review | A second model in its own shell, for example Codex | `<on request · every round · at stage close-out>` |
| The audit | The `project-setup` skill, audit mode | `on request` |
| Frozen-build pass | `ctl build save`, `ctl build start`, then a person | `on request` |
| Security review | `<not yet · walked on <date>>` | `on request` |
| Instruction review | The `instruction-writing` skill's rubric | `<on request · every change to this file>` |

## Deciding alone

- Decide and keep going: wording, names, the order of steps, test names. Asking parks the run for no gain.
- Decide and record here: a structural choice a skill page leaves open, an exception to the layout, a deferral past a tripwire. An unrecorded choice reads as drift at the next audit.
- Stop and ask: an irreversible outward action such as a push, a publish or a delete outside the repo; a product question no engineering principle settles; a change to a recorded choice above. A wrong guess here costs a restructure or cannot be undone.

## Escalation

For any structural decision this brief does not cover, or when a rule here looks wrong, load the `project-setup` skill and follow it. Do not improvise a pattern inline, because a pattern with no home cannot be found by the next agent. For a review pass, use the table above. The skill's `references/10a_review.md` is the full catalogue.

Before the first public deploy, load the `project-setup` skill and walk `references/09_production.md` § Checklist with the user. The gate ladder above is the prototype floor. That checklist is where the `audit` and `build` rungs, the security review and the hooks join, and each joins on the user's yes.
