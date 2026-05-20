# Topology 01 — single-app

A single CLI, library, or tool. No frontend, no microservices. Examples: `uvenv`, a one-off scraper, a small daemon.

## When it fits

- Exactly one runnable thing
- No frontend, no second backend
- Project may or may not have docker compose (for any external infra it needs)
- Project may or may not have docs

## Tree

```
my-tool/
├── .env / .env.example              # only if the tool reads env vars at runtime
├── .mise.toml                       # runtime version contract
├── dev                              # global wrapper (small)
├── apps/
│   └── <tool-name>/                 # always nested, never src/ at root
│       ├── pyproject.toml + uv.lock   # or Cargo.toml, go.mod, package.json
│       ├── config.yaml              # optional
│       ├── src/<package>/
│       ├── tests/
│       └── Dockerfile               # optional
├── docker/                          # optional — only if the tool needs infra
│   ├── compose.yaml
│   └── compose.dev.yaml
├── scripts/                         # optional — subscripts the wrapper calls
├── docs/                            # optional — use /docs-init
├── .claude/                         # empty initially
├── CLAUDE.md
├── README.md
└── LICENSE
```

## Why nest under `apps/<tool-name>/`?

Because today it's one tool, tomorrow there's a partner repo or a companion service. Nesting now means no restructuring later. The cost is one extra `cd` per command; the cost saved is renaming every import in every file.

The single exception is **languages where workspace nesting fights the toolchain** (e.g. plain Cargo project with one binary). Even then, default to `apps/<tool>/Cargo.toml` and use a workspace `Cargo.toml` at root for orchestration if a second crate appears.

## What's different from Topology 02

- No `apps/frontend/`
- No `infra/` (unless the tool ships infra config; rare)
- No `data/` (unless the tool persists state via compose; rare)
- `./dev` is small: usually just `./dev` (run), `./dev test`, `./dev build`, `./dev help`

## Real-world reference

- `uvenv` — `~/projects/02_OpenSource/02_dev_tools/uvenv` — does NOT yet follow this pattern (predates the convention; `src/` is at root). When the convention applies to it, migrate `src/` → `apps/uvenv/src/`.

## Escalation triggers

Move to Topology 02 when:

- A frontend is added (even a small admin dashboard)
- A second backend is added in a different language
- The tool grows to need a database it manages (rather than connecting to existing)

## Common mistakes to avoid

- Putting `src/` at repo root "because it's just one app." Don't. Nest.
- Adding `docker/`, `infra/`, `data/`, `scripts/` proactively. Add when needed.
- Writing a 200-line `./dev` wrapper for a tool. Keep it tight; if it grows, split subcommands into `scripts/`.
