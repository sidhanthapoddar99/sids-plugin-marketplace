# Layout 01 — single-app

The one-app repo shape: a single CLI, library, tool, or lone backend. No frontend, no second service. This file owns the **repo-level** shape only — where the one service folder sits and how the root stays clean. What goes *inside* that service (flat `app/` vs `src/`-layout, the skeleton) is an L3 decision, owned elsewhere and linked below.

## When it fits

- Exactly one runnable thing.
- No frontend, no second backend.
- Project may or may not have docker compose (for any external infra it needs).
- Project may or may not have docs.

Examples: a CLI packaged for distribution, a one-off scraper, a small daemon.

## Tree

**One service total → the code folder sits at the top level, NOT under `apps/`.** `apps/` is a grouping folder for *multiple* services (Layout 02+); with one service it is empty ceremony.

Distributable tool / library (src-layout earns its keep for packaging):

```
my-tool/
├── .env / .env.example              # only if the tool reads env vars at runtime
├── .mise.toml                       # runtime version contract
├── dev                              # global wrapper (small), if needed
├── <tool-name>/                     # top-level service folder (name is free)
│   ├── pyproject.toml + uv.lock     # or Cargo.toml, go.mod, package.json
│   ├── config.yaml                  # optional
│   ├── src/<package>/               # ← src-layout (distributable) — internals owned by references/3-app/backend/app-skeleton.md
│   ├── tests/
│   ├── Dockerfile                   # optional
│   └── README.md                    # this service's host dev loop
├── docker/                          # optional — only if the tool needs infra
│   └── compose.yaml                 # base, port-less, profile-less (+ standalone configs / .m. modifiers if needed — see references/2-repo/runtime/docker-overview.md)
├── scripts/                         # optional — subscripts the wrapper calls
├── docs/                            # optional — /agent-ks-init (references/1-ecosystem/docs-placement.md)
├── .claude/                         # empty initially
├── CLAUDE.md
├── README.md
└── LICENSE
```

Lone run-service (a backend with no frontend yet) — **flat `app/`, no `src/`**:

```
my-api/
├── .mise.toml
├── dev
├── api/                             # top-level (name is free: api / backend / …)
│   ├── pyproject.toml + uv.lock
│   ├── config.yaml
│   ├── app/                         # ← flat run-service — internals owned by references/3-app/backend/app-skeleton.md
│   │   ├── main.py
│   │   └── …
│   ├── alembic/                     # if it owns a DB
│   ├── tests/
│   ├── Dockerfile
│   └── README.md
├── docker/  data/  docs/  .claude/  CLAUDE.md  README.md  LICENSE
```

## Flat `app/` vs distributable `src/<pkg>/`

Which shape this repo's service uses — flat `app/` for a run-service (launched, never built into a wheel) vs `src/`-layout for a distributable package/CLI — is an L3 app-skeleton decision. Pick by what the thing *is*, not by habit. Owned by `references/3-app/backend/app-skeleton.md`; don't restate the rationale here.

## What's different from Layout 02

- No `apps/frontend/`.
- No `infra/` (unless the tool ships infra config; rare).
- No `data/` (unless the tool persists state via compose; rare).
- `ctl` is small: usually just `ctl dev` (run), `ctl test`, `ctl build`, `ctl help`.

## Real-world reference

See `references/handoffs/examples-registry.md` — cite a registered single-app repo if one exists; never invent paths. Note: a pure shell tool keeping `src/` + `lib/` at root is normal for shell projects; the Python `app/` vs `src/` distinction applies to Python services, not shell scripts.

## Escalation triggers

Move to Layout 02 (`references/2-repo/layouts/02_multi-app-monorepo.md`) when a second runnable thing appears — a frontend (even a small admin dashboard), a second backend, or a database this repo manages: introduce `apps/` then and move both under it. Escalation rules table: `references/02_decision-tree.md`.

## Anti-patterns

- **Loose code in the repo root** — putting `main.py`, `app/`, or `src/` directly in the repo root "because it's just one app." Keep the root clean; the code goes in a top-level service folder (`./<name>/`). Running `npm init` / `uv init` at the repo root has the same effect: the manifest, `node_modules/`, and run scripts take over the root. The only sanctioned root-manifest cases (editor extensions, a pure OSS package repo) are a *recorded* exception — see `references/2-repo/root-and-hygiene.md`.
- **Nesting a single service under `apps/<name>/`** — `apps/` is for 2+ services; for one, use top-level `./<name>/`.
- **Wrong inner shape** — using `src/` for a run-service backend, or flat `app/` for a distributable. The run-service-vs-src-layout rule is owned by `references/3-app/backend/app-skeleton.md`.
- **Proactive scaffolding** — adding `docker/`, `infra/`, `data/`, `scripts/` before they're needed. Add when needed.
- **A heavyweight `ctl`** — writing a 200-line dispatcher for a tool. Keep it tight; if it grows, split subcommands into `scripts/`.

## See also

- `references/2-repo/layouts/02_multi-app-monorepo.md` — 2+ apps (step up)
- `references/2-repo/root-and-hygiene.md` — root contract, single-package containment, gitignore
- `references/3-app/backend/app-skeleton.md` — flat `app/` vs `src/`-layout, pyproject + uv flow, the skeleton
- `references/2-repo/runtime/overview.md` — the runtime triad (`ctl`/docker/mise)
- `references/handoffs/examples-registry.md` — registered real repos to cite
