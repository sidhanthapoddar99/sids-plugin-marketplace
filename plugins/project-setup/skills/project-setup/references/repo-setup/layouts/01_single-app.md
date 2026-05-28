# Layout 01 — single-app

A single CLI, library, or tool. No frontend, no microservices. Examples: `uvenv`, a one-off scraper, a small daemon.

## When it fits

- Exactly one runnable thing
- No frontend, no second backend
- Project may or may not have docker compose (for any external infra it needs)
- Project may or may not have docs

## Tree

**One service total → the code folder sits at the top level, NOT under `apps/`.** `apps/` is for grouping *multiple* services (Layout 02+).

Distributable tool / library (src-layout earns its keep for packaging):

```
my-tool/
├── .env / .env.example              # only if the tool reads env vars at runtime
├── .mise.toml                       # runtime version contract
├── dev                              # global wrapper (small), if needed
├── <tool-name>/                     # top-level service folder (name is free)
│   ├── pyproject.toml + uv.lock     # or Cargo.toml, go.mod, package.json
│   ├── config.yaml                  # optional
│   ├── src/<package>/               # ← src-layout: distributable package/CLI
│   ├── tests/
│   ├── Dockerfile                   # optional
│   └── README.md                    # this service's host dev loop
├── docker/                          # optional — only if the tool needs infra
│   └── compose.yaml                 # profiled base, port-less (+ .m. modifiers if needed — see runtime/docker-overview.md)
├── scripts/                         # optional — subscripts the wrapper calls
├── docs/                            # optional — use /docs-init
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
│   ├── app/                         # ← flat: run-service, never packaged
│   │   ├── main.py
│   │   └── …
│   ├── alembic/                     # if it owns a DB
│   ├── tests/
│   ├── Dockerfile
│   └── README.md
├── docker/  data/  docs/  .claude/  CLAUDE.md  README.md  LICENSE
```

## Why top-level, not `apps/`?

`apps/` is a grouping folder — it earns its place once there are 2+ services to group. For a single service it's empty ceremony. Keep the root clean (config + README + folders) and put the one service folder directly at the top level. If a second service appears later, *that's* when you introduce `apps/` and move both under it (Layout 02 escalation).

## Why `app/` (flat) for a run-service and `src/<pkg>/` for a distributable?

- A **run-service** (FastAPI/Flask/worker) is launched, never built into a wheel. `src/` only adds `PYTHONPATH` / `prepend_sys_path` plumbing for zero benefit. Flat `app/` matches the official full-stack FastAPI template.
- A **distributable package/CLI** (like `uvenv`-as-a-package) benefits from src-layout: it forces tests to import the *installed* package, catching "works in dev because of cwd, breaks when installed" bugs.

Pick by what the thing *is*, not by habit. See `references/architecture/backend/pyproject-uv-sync-for-apps.md`.

## What's different from Layout 02

- No `apps/frontend/`
- No `infra/` (unless the tool ships infra config; rare)
- No `data/` (unless the tool persists state via compose; rare)
- `ctl` is small: usually just `ctl dev` (run), `ctl test`, `ctl build`, `ctl help`

## Real-world reference

- `uvenv` — `~/projects/02_OpenSource/02_dev_tools/uvenv` — a shell tool (its code is `src/` + `lib/` at root, which is normal for a shell project, not the Python layout above). Cited as a single-tool example; the Python `app/` vs `src/` distinction applies to Python services, not shell scripts.

## Escalation triggers

Move to Layout 02 when:

- A frontend is added (even a small admin dashboard)
- A second backend is added in a different language
- The tool grows to need a database it manages (rather than connecting to existing)

## Common mistakes to avoid

- Putting loose code (`main.py`, `app/`, `src/`) directly in the repo root "because it's just one app." Don't — keep the root clean; the code goes in a top-level service folder (`./<name>/`).
- Nesting a single service under `apps/<name>/`. `apps/` is for 2+ services; for one, use top-level `./<name>/`.
- Using `src/` for a run-service backend. Flat `app/` — `src/` is for distributable packages and frontends.
- Adding `docker/`, `infra/`, `data/`, `scripts/` proactively. Add when needed.
- Writing a 200-line `ctl` dispatcher for a tool. Keep it tight; if it grows, split subcommands into `scripts/`.
