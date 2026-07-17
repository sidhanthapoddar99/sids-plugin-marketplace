# `ctl` + `scripts/` — the control-plane model

One executable at repo root — `ctl` — is the single entrypoint for the whole stack: local dev processes **and** containers. It's the project's user-facing API. This doc is the **mental model**; the command surface, the dispatcher skeleton, the `scripts/*.sh` map, and the exact commands live in `01_script-usage.md`.

> **These code blocks are ILLUSTRATIVE.** The source of truth is the runnable snippet under **`assets/snippets/scripts/<file>`** — copy it verbatim, then adapt. Do not regenerate the scripts from this prose; the prose is intentionally abbreviated and will produce a worse result than the file. **Asset path:** `assets/` is a sibling of `skills/` at the **plugin root** — NOT under `skills/project-setup/`.

> **Name.** `ctl` is a single swappable token (`stack`, `app`, or the project name) — pick one, keep it. With mise's project-scoped PATH you call it bare — `ctl up`, not `./ctl`. See `references/2-repo/06-runtime-environment/01_mise.md`.

## One host launcher, one docker launcher

Two kinds of thing have two lifecycles, so they get two grammars:

| Kind | Lifecycle | Commands |
|---|---|---|
| **Local dev loop** (apps on host, hot reload) | interactive, foreground — Ctrl-C stops | `ctl dev` |
| **Containerised stack** | detached, long-lived | `ctl up [config] [--modifier "a,b"]` · `down` · `ps` · `logs` |

`ctl dev` runs apps **on the host** — genuinely *not* a compose variant, so it's its own verb. Everything that runs **in docker** goes through `ctl up`. There is **no `ctl prod` verb**: production is `ctl up prod` (a standalone config).

### `ctl up`'s two axes (concept)

Profile-less. The stack is shaped by exactly two axes:

- **Config** — *which scenario.* At most one. The base `compose.yaml` (the whole stack) is the default; a named `compose.<name>.yaml` is a **standalone** scenario that **replaces** base (`data` = just the data layer, `prod` = the hardened stack).
- **Modifiers** — stackable cross-cutting overlays layered on the chosen config (`--modifier expose`, `--modifier expose_data,traefik`).

There is **no profiles axis** — every service in the chosen file runs. (Profiles are a rare advanced escalation for multi-group meshes; see `03_complex-setups.md`.) The compose-file convention behind these (filenames, the standalone-vs-overlay choice, expose tiers, discovery) is owned by `references/2-repo/04-docker/00_docker-overview.md`; the exact `ctl up` grammar, the interactive flow, and the assembled `docker compose` line are in `01_script-usage.md`.

### `ctl up` is interactive (and still scriptable)

Bare `ctl up` in a terminal is a guided flow — **pick config → pick modifiers → see a plan → confirm (Run / Back / Cancel)** — built on a dependency-free TUI (`scripts/common/_select.sh`, no `fzf`/`gum`). It prompts only for the axes you didn't pass on the CLI, renders the real merged plan (`docker compose config` — services, ports, networks, volumes; this also validates the combo early), and prints the exact `--nqa` command that reproduces the run. CI (no TTY) and `--nqa` keep the deterministic flag path untouched. Mechanics in `01_script-usage.md`.

## Thin wrapper — delegate, don't hand-roll

`ctl` is **thin routing**, never a 500-line supervisor (that would fight the modularity caps). It delegates:

- **Containers → `docker compose`.** `up`/`down`/`ps`/`logs`/`restart` are thin wrappers; `up`'s logic is turning a config + modifiers into a `-f`/`--env-file` list, planning it, then echoing and running it.
- **Local multi-process dev → a real runner**, not bash PID juggling. Default **`process-compose`** (declarative `process-compose.yaml`, readiness probes, per-service panes); **`mprocs`** as a lighter option; a bash `trap` only as a 1–2-process fallback (`scripts/dev/host.sh`).
- **Real command bodies → `scripts/<category>/<name>.sh`**, each owning one job (the trivial one-liners `down`/`restart`/`logs`/`exec` stay inline in `ctl`). See the structure below.
- **Shared concerns → `scripts/common/_lib.sh`**, sourced by `ctl` and every worker: the color palette + indent-aware logging, the `row()` aligned-help helper, the uniform `--help` renderer, the `dc()`/discovery/health helpers, env/tool guards. It sources **`scripts/common/_select.sh`** (the picker). This is what lets each worker stay ~25 lines and look identical.

## The `scripts/` structure — what you create

`ctl` routes; `scripts/<category>/<name>.sh` are the workers, **grouped into category folders** so the directory reads as a toolkit. Each sources `common/_lib.sh`, is self-contained (`set -euo pipefail`, exits non-zero, runnable on its own), and ships a `-h/--help`.

```
scripts/
├── common/             # shared, sourced not routed
│   ├── _lib.sh         # colors, indent-aware logging, row()/print_help, dc()+discovery, guards, health
│   └── _select.sh      # dependency-free TUI (tui_select) — single/multi/horizontal; sourced by _lib.sh
├── dev/                # host-loop / development workflow
│   ├── host.sh         # ctl dev      — ensure data core (if any), run apps on host (process-compose|bash)
│   ├── migrate.sh      # ctl migrate  — alembic up/down/new/status
│   ├── test.sh         # ctl test     — pytest + bun test
│   └── lint.sh         # ctl lint     — ruff + biome (check; stack-specific)
├── container/          # container & compose lifecycle
│   ├── up.sh           # ctl up       — interactive 2-axis assembly: config (replaces base) + .m. modifiers (+ plan/--list)
│   ├── build.sh        # ctl build    — service images
│   ├── clean.sh        # ctl clean    — teardown + wipe volumes/caches (asks; -y to skip)
│   ├── health.sh       # ctl health   — one-shot health table
│   ├── shell.sh        # ctl shell    — psql / redis-cli / shell in a container
│   └── ps.sh           # ctl ps       — containers + host dev processes (by dev port → PID)
└── config/             # config management
    ├── setup.sh        # ctl setup    — .env wizard + secrets + data dirs + deps (project-custom)
    ├── status.sh       # ctl status   — doctor: env·runtimes·docker·deps·health·stack (project-custom)
    └── check-env.sh    # helper       — .env vs .env.example schema diff (used by status)
```

| Folder | Holds | Backing `ctl` verbs |
|---|---|---|
| `common/` | shared libs, sourced not routed | `_lib.sh`, `_select.sh` |
| `dev/` | host-loop / development workflow | `dev`, `migrate`, `test`, `lint` |
| `container/` | container & compose lifecycle | `up`, `build`, `clean`, `health`, `shell`, `ps` |
| `config/` | config management | `setup`, `status` (+ `check-env` helper) |

Layout is **`scripts/<category>/<name>.sh`** (`category ∈ common | dev | container | config`). The folder groups; the `ctl` subcommand stays clean — file `dev/migrate.sh`, command `ctl migrate` (not `ctl dev/migrate`). Trivial `docker compose` passthroughs (`down`/`restart`/`logs`/`exec`) are **not** files — they're one-line forwards inlined in `ctl`, still shown under the Containers group with uniform help.

**Treat the shipped set as a template, not a spec.** It's a sensible default — copy `ctl` + `scripts/`, then add / remove / edit per the project; most repos won't need every command, and `migrate`/`lint`/`shell`/`test` are stack-specific (adapt or drop — a no-DB repo drops `migrate`). How many files is **utility-driven**: a command earns a file once it outgrows a one-liner. **To add a command:** drop `scripts/<category>/<name>.sh` (worker preamble + `usage()` + `is_help` guard, sourcing `common/_lib.sh`) and wire one `run <category>/<name>` line into `ctl`'s `case`. The runnable toolkit lives in `assets/snippets/scripts/`; `01_script-usage.md` has the architecture + worked bodies.

## The conformance floor — adapt by deletion, never by collapse

"Template, not spec" licenses **subtraction and substitution — never architectural collapse**. A conforming installation, at minimum:

1. **Install = copy, then adapt.** The runtime layer is installed by copying `assets/snippets/scripts/` wholesale (`cp -r`), then deleting/editing per the project — never by authoring a dispatcher from memory of this prose.
2. `ctl` at the repo root **sources `scripts/common/_lib.sh`** and stays a thin router.
3. `scripts/common/_lib.sh` **and `_select.sh`** are present (they're what keep every worker ~25 lines and uniform).
4. Every substantive verb the project keeps **routes to a `scripts/<category>/<name>.sh` worker**; only the trivial `docker compose` passthroughs (`down`/`restart`/`logs`/`exec`) are inlined.
5. Workers keep the standard shape: preamble sourcing `_lib.sh`, `set -euo pipefail`, `-h/--help`, runnable standalone.

A no-DB repo deleting `migrate.sh`, a bun→pnpm swap inside `dev/host.sh` — sanctioned adaptation (`02_script-alternatives.md`, `references/2-repo/04-docker/02_no-data-core.md`). A **single-file `ctl` with command bodies inlined and no `scripts/` tree is not an adaptation — it's a different (non-conforming) architecture**, and audits flag it red. The floor is checkable mechanically: `_lib.sh` sourced? `common/` present? each non-passthrough verb `run`-routed?

## `setup` + `status` — the two project-custom bodies

Every `ctl` verb is uniform across projects **except two**, whose logic is necessarily case-by-case (which env keys, which services, frontend-vs-backend checks):

- **`ctl setup`** — fills `.env`: copy `.env.example`, generate secrets (`openssl rand`), make data dirs (if a data core), install deps (`uv sync` + `bun install`). Re-runnable — tops up missing values, never clobbers good ones.
- **`ctl status`** — read-only config doctor answering "is this correctly configured to run?" *before* `ctl dev` hits a confusing runtime error. Reports env · runtimes (mise + uv/bun/uvenv) · docker · deps · data-core health · the discoverable stack (configs + modifiers).

First run is `ctl setup` → `ctl dev`. Setup is **explicit**, never folded silently into a bare run: `ctl dev` only *guards* (`.env` missing → "run `ctl setup`"); it never mutates config mid-launch. Prod secrets are injected as real env vars (`.env.production` via compose `env_file`), never via the wizard.

## Why apps on host for dev

`ctl dev` runs apps on the host, only data services in containers:

| Containerised apps in dev | Apps on host (`ctl dev`) |
|---|---|
| Total prod parity | Faster iteration |
| Slow bind-mount file watching (esp. macOS) | Native file events |
| Complex debugger attach (port mapping) | IDE attaches directly to the local process |
| `restart` to pick up changes | native `--reload` / `bun dev` / `cargo-watch` |

Parity is enforced by CI building images and by `ctl up` running them — you don't *develop* against the image. Source is never bind-mounted into a dev container. When you want the containerised stack, that's `ctl up`, not `ctl dev`.

## Three startup paths (every README documents all three)

1. **`ctl dev`** — the dispatcher; recommended day-to-day path.
2. **Raw `docker compose -f docker/…`** — understand what `ctl` does; debug compose itself; copy for prod.
3. **No-docker host run** — `cd apps/backend && uv run …; cd apps/frontend && bun dev` — IDE debugger attach, profiling, one service in isolation.

If any of the three is broken or missing, the project has invisible debt. The exact commands + README snippet are in `01_script-usage.md`; the full README contract + audit checklist is owned by `references/2-repo/02-root-hygiene/01_readme-three-paths.md`.

## One dispatcher per repo

A repo has **one** `ctl`. New need → a standalone config, a `compose.m.<mod>.yaml`, or a subcommand — not a second wrapper. The one exception is Layout 03 (polyrepo + aggregator): each child repo has its own `ctl`, and the aggregator has its own whose `ctl up prod` deploys the merged stack. When `ctl` itself outgrows shell (structured state across runs, multi-node promotion), escalate it to a binary — see `03_complex-setups.md`.

## Anti-patterns

- `setup.sh` + `start.sh` + `dev.sh` at root — four contracts; collapse to `ctl` verbs.
- A 500-line bash wrapper reimplementing a process manager — delegate to `process-compose`/`docker compose`.
- A single-file `ctl` with command bodies inlined "for now" — below the conformance floor; it never grows the `scripts/` tree later, it just grows.
- A `ctl prod` verb separate from `ctl up` — production is just a config; two verbs for one lifecycle drift apart.
- Reaching for profiles by default — the simple path is profile-less (config + modifiers); profiles are the rare multi-group escalation (`03_complex-setups.md`).
- `ctl dev` silently editing `.env` on launch — guard and instruct; mutation belongs in `ctl setup`.
- README "first run `make install`, then `make dev`" — it's `ctl setup` then `ctl dev`.
- Bind-mounting source into a dev container — slow file events, permission pain; run on host.
- Regenerating the snippets from this prose instead of copying `assets/snippets/scripts/` — the file is the source of truth.

## See also

- `01_script-usage.md` — command surface, dispatcher skeleton, the interactive `ctl up` flow + plan screen + `--list`, the `scripts/*.sh` map, setup/status detail, how to add/modify scripts
- `02_script-alternatives.md` — adapting the workers off the recommended defaults (no mise / docker / uv→uvenv·venv·poetry / bun→pnpm·npm)
- `references/2-repo/04-docker/02_no-data-core.md` — `DATA_SVCS=()` + apps-as-core: the lines to change for a DB-less project
- `references/2-repo/04-docker/00_docker-overview.md` — the standalone-config / `.m.` modifier compose convention `ctl up` implements
- `references/2-repo/06-runtime-environment/01_mise.md` — the project-scoped PATH that makes `ctl` callable bare
- `03_complex-setups.md` — profiles as the advanced escalation; when `ctl` outgrows shell (multi-node, Go-CLI orchestrator)
- `references/2-repo/06-runtime-environment/00_runtime-triad.md` — the whole-runtime interaction map (mise → ctl → docker)
