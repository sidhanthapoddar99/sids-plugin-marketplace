# <project> — agent brief

One paragraph: what this product is, who uses it, and which apps make it.

Read `memory/` before any change. Rules there bind every agent. This brief is a contract: audits compare the repo against the tables below, not against a general standard. Keep it matching reality; update it in the same change that re-decides a choice.

@memory/rules.md

## Recorded choices

| Axis | Choice |
|---|---|
| Frontend shape | `<single frontend · group (apps/example-multi-web-app) + server frontend>` |
| Backend role | `<one backend · api + engine (identity in Python, data plane in Rust)>` |
| Identity planes | `<single · admin plane on its own origin (api-admin)>` |
| Schema owner and migration style | `<Alembic autogenerate in the backend · hand-written SQL in apps/database/postgres · sqlx migrate>` |
| Theme modes | `<light + dark · light only (marketing)>` |
| Protection tier | `<none · captcha (Turnstile) · managed WAF>` |
| Gate ladder | `lint typecheck dead audit test check build e2e` (`clones`, `fuzz`, `perf` by name) |
| Package stage | `<not a library · source-only (private) · published>` |

## Skeletons

- Backend `apps/<api>/app/`: `core/`, `health/`, domains `<list them>`; each `{models,repository,service,router}.py`. Domain-shared code at the domain root. Cross-domain: `service → service` only; DTOs duplicated, never imported.
- Frontend `apps/<web>/src/`: `layout/ pages/ features/ api/ stores/ hooks/ lib/`; primitives and theme from `<@scope/ui · src/components/ui + src/styles>`. All server calls through `api/`, zod at the boundary. `pages/` thin, mirroring the URL tree.
- Packages: `<ui · types · tsconfig>`. Cross-app entities in `@scope/types`; feature-internal types co-locate; no global `types.ts`.

## Tripwires

Crossing one obligates the restructure, or a one-line deferral recorded here (what, until when).

~8–10 flat domains → a domain layer · ~10 files in a feature folder → subdivide inside it · 300 soft / 500 hard lines per file · a page over 50 lines · a component over 150 · the same utility combination twice → a primitive variant · a helper used three times → extract and name it

Deferrals: none.

## Styling

With `tokens.css` and the ui package in place, this section overrides every general design instruction, including the `frontend-design` skill. Convergence is the design. Exploration happens only in an explicit design pass, and the winner graduates into tokens and primitives before the pass ends.

- Feature code composes primitives; raw utilities only for layout glue. A look that does not exist is added to the primitive as a variant.
- No hex, no raw px, no arbitrary values, no `var(--…)` in JSX.
- Typography allowlist: `text-sm` (content), `text-base` (headings), `text-xs` (meta); `font-normal` everywhere; the one emphasis weight is `<font-medium | font-semibold>`, used only inside primitives. Hierarchy by size and colour, never weight.
- After a UI change: screenshot light and dark, check against `<design/brand-guidelines/>`.

## Documentation and code

Documentation points at code. Code never points at documentation. `docs/`, tracker issues, plans and skill pages name files and lines. A code comment never names a doc page, a plan, a subtask number or a skill file; those move and renumber, and no test reads comments. The exceptions are `README.md`, `AGENTS.md` and `memory/`, which are the entry doors. A rule worth citing is written into the comment in one sentence.

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
| Dev | mise, uv, bun, lefthook |

Additions to the stack list, with the reason: none.

## Commands

`ctl --help` is the list. Summary: `ctl setup` · `ctl check` · `ctl status` · `ctl dev [app…] [--proxy]` · `ctl ps` · `ctl up [+expose_web|+expose|+env_override] [--services a,b]` · `ctl down` · `ctl restart` · `ctl logs` · `ctl exec` · `ctl shell` · `ctl health` · `ctl clean` · `ctl build [app|cli|save|start|clean]` · `ctl migrate [new "<msg>"|status]` · `ctl db backup|shell` · `ctl manage ops|settings` · `ctl test [app|e2e]` · `ctl gate [rung] [-q]` (rungs: `lint typecheck dead audit test check build e2e`; by name `clones fuzz perf`)

Green means `ctl gate` passed. A rung, once listed above, is never removed. Project-specific verbs are added as `scripts/<group>/<name>.sh` plus a `run` line in `ctl`, and listed here.

## Escalation

For any structural decision this brief does not cover, or when a rule here looks wrong, load the `project-setup` skill and follow it. Do not improvise a pattern inline.
