# Example 01 — single distributable CLI

Layout 01, the smallest conforming repo. One runnable thing, no frontend, no second backend, no database. Variant set shown: a **distributable** Python CLI (published to an index) → **src-layout**; a **minimal `ctl`** with no docker verbs; **no compose, no `data/`, no `infra/`**. Substitute the tool name (`tablefmt` here — a CLI that reformats tabular data files) and language freely; the shape is the lesson.

This is the runtime floor and nothing else: a repo that still satisfies the `ctl` conformance floor (`references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`) while carrying none of the stack that Example 02 adds.

## Tree

```
tablefmt/                            # repo root — an INDEX, not a runtime: config + README + folders, no loose code
├── .mise.toml                       # runtime version contract (pins python); makes `ctl` callable bare on PATH
├── ctl                              # thin dispatcher — dev/test/build/lint/help ONLY; no docker verbs (no compose)
├── scripts/                         # ctl workers, grouped by category; sourced-not-routed common lib
│   ├── common/
│   │   ├── _lib.sh                  # colors, indent-aware logging, uniform --help renderer, tool guards — sourced by ctl + every worker
│   │   └── _select.sh              # dependency-free TUI picker; sourced by _lib.sh (kept even when unused, per the floor)
│   ├── dev/
│   │   ├── run.sh                   # ctl dev  — run the CLI from source (`uv run tablefmt …`)
│   │   ├── test.sh                  # ctl test — pytest against the INSTALLED package
│   │   └── lint.sh                  # ctl lint — ruff check + format
│   └── build/
│       └── package.sh               # ctl build — `uv build` → wheel + sdist into dist/
├── tablefmt/                        # top-level SERVICE folder (one service → NOT under apps/; same name as repo is fine)
│   ├── pyproject.toml               # deps + [build-system] + [tool.uv] package = true  (it IS built into a wheel)
│   ├── uv.lock                      # committed — reproducible exact dep tree
│   ├── .venv/                       # gitignored — created by `uv sync`
│   ├── config.yaml                  # optional — only if the CLI reads config at runtime
│   ├── src/                         # ← SRC-LAYOUT: distributable package
│   │   └── tablefmt/                # the package; tests import the INSTALLED copy, not the working tree
│   │       ├── __init__.py
│   │       ├── __main__.py          # `python -m tablefmt` entry
│   │       ├── cli.py               # arg parsing + command dispatch (Click/argparse) — thin, delegates into formats/
│   │       ├── core/                # shared internals: config load, io helpers (the "lowest level containing all consumers")
│   │       │   ├── config.py
│   │       │   └── io.py
│   │       └── formats/             # feature folders — one module per supported format; subdivides at tripwire T3
│   │           ├── csv.py
│   │           └── json.py
│   ├── tests/                       # mirrors src/; imports the installed package (that's what src-layout buys)
│   │   ├── test_csv.py
│   │   └── test_json.py
│   └── README.md                    # THIS service's host dev loop (the run paths that apply: dispatcher + raw host)
├── docs/                            # optional — hand off to the docs plugin via /agent-ks-init if it needs a site
├── .claude/                         # empty initially — the CLAUDE.md blocks carry the recorded structure
├── CLAUDE.md                        # repo role + (no) siblings, chosen variants (distributable/src-layout), tripwire numbers, escalation pointer
├── README.md                        # root INDEX: what it is, `pip install tablefmt`, usage, links inward to the service README
└── LICENSE
```

**No `docker/`, no `data/`, no `infra/`, no `apps/`, no frontend.** Each is empty ceremony for a single no-infra CLI; add only when a real need arrives (see Escalation).

### Why these variant choices

- **src-layout, not flat `app/`.** This CLI is *built into a wheel and published*. src-layout forces tests to import the installed package, catching "works because of cwd, breaks when installed" bugs. A backend that's only *launched* (never installed) would use flat `app/` instead — the run-service column. The decision, `[tool.uv] package`, and `pytest.pythonpath` are owned by `references/3-app/02-backend/00_app-skeleton.md`.
- **Service folder at top level, not `apps/tablefmt/`.** `apps/` is a grouping folder; it earns its place at 2+ services. For one, the code sits in a top-level `./tablefmt/` and the root stays clean.
- **Minimal `ctl`, no docker verbs.** No compose means no `container/` category and no `ctl up`. The floor still holds: `ctl` sources `common/_lib.sh`, `common/` is present, and every substantive verb routes to a `scripts/<category>/<name>.sh` worker.

### Variant — the sanctioned root-manifest exception

A *pure* OSS package repo (nothing but the published package) may flatten: `pyproject.toml` + `src/tablefmt/` + `tests/` directly at the repo root, no inner service folder. This is the one sanctioned root-manifest case — but it is a **recorded exception** (a line in CLAUDE.md), not the default. Take it only when the repo will never grow a second service; the moment a CLI, a docs site with its own build, or infra appears, the un-flattened form above is what scales. Owned by `references/2-repo/02-root-hygiene/00_root-and-hygiene.md`.

## Escalation triggers → Layout 02

Recorded in CLAUDE.md; when one trips, re-open `references/02_decision-tree.md`:

- A frontend is added (even a small admin dashboard) → introduce `apps/`, move the service under it.
- A second backend in another language is added.
- The CLI grows to *manage* a database (not just connect to one) → it needs `data/`, compose, migrations.
- `ctl` outgrows shell (structured state across runs) — tripwire T7 → escalate to a binary (`references/2-repo/05-ctl-scripts-tooling/03_complex-setups.md`).

## Which references govern what

| Part of the tree | What it is | Governed by |
|---|---|---|
| repo root layout, one service at top level, no `apps/` | the single-app shape + when it fits | `references/2-repo/01-layouts/01_single-app.md` |
| root as index, single-package containment, `.gitignore`, root-manifest exception | root contract | `references/2-repo/02-root-hygiene/00_root-and-hygiene.md` |
| `src/tablefmt/` vs flat `app/`, `pyproject.toml`, `[tool.uv] package = true`, `uv.lock`, `pytest.pythonpath = ["src"]` | run-service vs distributable + the uv flow | `references/3-app/02-backend/00_app-skeleton.md` |
| `core/` (shared internals) placement | code at the lowest level containing all consumers | `references/3-app/02-backend/00_app-skeleton.md` |
| `formats/` feature modules; internal subdivision | feature-folder shape + T3 | `references/4-feature/feature-folders.md` |
| when `formats/` crosses the T2 threshold → a domain layer | T2 domain grouping | `references/3-app/02-backend/01_domain-grouping.md` |
| file/function size caps (T5), rule-of-three extraction (T9), folders-by-feature | modularity caps | `references/4-feature/caps-and-extraction.md` |
| `ctl` + `scripts/{common,dev,build}/` + conformance floor | control-plane model | `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md` |
| `ctl` verb bodies, worker skeleton, adding a command | dispatcher mechanics | `references/2-repo/05-ctl-scripts-tooling/01_script-usage.md` |
| `.mise.toml`, bare `ctl` on PATH, python pin | runtime version contract | `references/2-repo/06-runtime-environment/01_mise.md` |
| service `README.md` (run paths) + root `README.md` index | README contract | `references/2-repo/02-root-hygiene/01_readme-three-paths.md` |
| `config.yaml` / `.env` precedence (if the CLI reads config) | env + config flow | `references/2-repo/03-env-config/00_env-precedence.md` |
| `docs/` + `/agent-ks-init` handoff | in-repo vs separate docs | `references/1-ecosystem/docs-placement.md` |
| `.claude/` empty + CLAUDE.md template (role, variants, tripwire numbers, escalation pointer) | delivery mechanism | `references/handoffs/claude-folder.md` |
| the L2 decision index this repo instantiates | repo-level charter | `references/2-repo/00_index.md` |

## See also

- `references/5-examples/00_index.md` — how to read these examples + the full example↔layout↔variants map
- `references/5-examples/02_canonical-1be-1fe.md` — what this repo becomes once a backend + frontend + compose arrive (Layout 02)
- `references/2-repo/04-docker/02_no-data-core.md` — the `DATA_SVCS=()` adaptation for any DB-less runtime
