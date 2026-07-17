# Snippets

Fragments the `project-setup` skill cites and `/ps-setup` can drop into a new or existing project. **Not** a full project template — focused pieces grouped by domain.

## Layout

```
assets/snippets/
├── frontend/          # CSS tokens, theme wiring, vite config
├── docker/            # profile-less compose base + standalone configs + .m. modifiers
├── infra/             # config baked into containers (nginx)
├── python/            # alembic helpers + shim template
├── env/               # .env.example + .mise.toml templates
├── scripts/           # thin ctl dispatcher + common/ (_lib.sh + _select.sh) + dev/ container/ config/ workers
└── claude/            # CLAUDE.md template
```

## Index

### `frontend/`

| File | What it is | Drops at |
|---|---|---|
| `tokens.css` | Design tokens — `--bg-*`, `--fg-*`, `--space-*`, `--radius-*`, light + dark | Layout 02 (single frontend): `apps/<frontend>/src/styles/tokens.css`. Layout 02 (multi-frontend): `packages/styles/src/tokens.css` |
| `globals.css` | Base resets + tailwind directives + shadcn alias mapping | `apps/<frontend>/src/styles/globals.css` |
| `light-dark.css` | Theme transitions, scrollbar styling, selection | `apps/<frontend>/src/styles/light-dark.css` |
| `vite-proxy.config.ts` | `vite.config.ts` with `/api/*` + `/ws` proxy | `apps/<frontend>/vite.config.ts` |

### `docker/`

**Profile-less, two axes.** `compose.base.yaml` is the base (the whole stack, no profiles, no host ports); a `compose.<name>.yaml` is a **standalone config** that *replaces* base (`data`, `prod`); `compose.m.<name>.yaml` files are stackable `.m.` modifiers. `ctl up [config] [--modifier "a,b"]` assembles them (bare `ctl up` is interactive). Full convention: `references/2-repo/04-docker/00_docker-overview.md`.

| File | What it is | Drops at |
|---|---|---|
| `compose.base.yaml` | Base — the whole stack, no profiles, no host ports, internal net; nginx healthcheck active, app ones commented | `docker/compose.base.yaml` |
| `compose.data.yaml` | Standalone config (`ctl up data`) — just postgres + redis (the data-layer slice; worked example) | `docker/compose.data.yaml` |
| `compose.prod.yaml` | Standalone config (`ctl up prod`) — image tags, resource limits, `.env.production` | `docker/compose.prod.yaml` |
| `compose.m.expose.yaml` | `--modifier expose` — publish nginx (the edge) only | `docker/compose.m.expose.yaml` |
| `compose.m.expose_data.yaml` | `--modifier expose_data` — publish postgres + redis (`ctl dev` layers it) | `docker/compose.m.expose_data.yaml` |
| `compose.m.expose_all.yaml` | `--modifier expose_all` — publish every service (debug) | `docker/compose.m.expose_all.yaml` |
| `compose.m.traefik.yaml` | `--modifier traefik` — external Traefik network + labels on the edge | `docker/compose.m.traefik.yaml` |

### `infra/`

| File | What it is | Drops at |
|---|---|---|
| `nginx.conf` | Routes `/api/*` to backend container, serves SPA, handles `/ws/*` | `infra/nginx/nginx.conf` |

### `python/`

| File | What it is | Drops at |
|---|---|---|
| `alembic-shim.py` | Three-file revision pattern shim | `apps/backend/alembic/versions/<rev>.py` (per migration) |
| `alembic_helpers.py` | `run_sql` helper imported by the shim | `apps/backend/alembic_helpers.py` |

### `env/`

| File | What it is | Drops at |
|---|---|---|
| `env.example.template` | `.env.example` with categories + `openssl rand` instructions | `.env.example` at repo root |
| `mise.toml.example` | `.mise.toml` template (versions illustrative) | `.mise.toml` at repo root |

### `scripts/`

**This is a template, not a fixed spec.** It's a sensible default toolkit — copy `ctl` (to the repo root, `chmod +x`, no extension — it's the public API) **and the whole `scripts/` folder**, then add / remove / edit commands to fit the project. Most repos won't need every command shipped here; some (`lint`, `shell`) are stack-specific — adapt or drop them.

`ctl` is a thin router; `scripts/common/_lib.sh` is the shared foundation (colors + indent-aware logging, `row()` aligned help, uniform `--help`, `dc()` + discovery, `or_none`, guards, container-resolved health) every worker sources; `scripts/common/_select.sh` is a dependency-free TUI picker (no fzf/gum) sourced by `_lib.sh` and used by the interactive `ctl up`. Each command with a real body is a worker at **`scripts/<category>/<name>.sh`** (category ∈ `dev` | `container` | `config`; `common/` holds the shared libs — the `ctl` verb stays clean: `ctl migrate`, file `dev/migrate.sh`). Trivial `docker compose` forwards (`down`/`restart`/`logs`/`exec`) stay inline in `ctl`. Colors auto-disable when piped or `NO_COLOR` is set; every command takes `-h`/`--help`.

**To add a command:** drop `scripts/<category>/<name>.sh` (use the worker preamble in `common/_lib.sh`) and wire one `run <category>/<name>` line into `ctl`'s `case`. See `references/2-repo/05-ctl-scripts-tooling/00_script-overview.md` (model + map) and `.../01_script-usage.md` (commands).

| File | What it is | Drops at |
|---|---|---|
| `ctl` | dispatcher — routes every subcommand, inlines trivial compose forwards, executable | `ctl` at repo root (chmod +x) |
| `common/_lib.sh` | **shared foundation** sourced by `ctl` + all workers (colors + `LOG_INDENT` logging, `row()`/`print_help`, `dc()`+discovery+`or_none`, guards, container-resolved health, `split_csv`, `confirm`); sources `_select.sh` | `scripts/common/_lib.sh` |
| `common/_select.sh` | **dependency-free TUI picker** (`tui_select`: single/multi/horizontal, arrow+jk nav, `[x]`, numbered fallback) — copy verbatim; used by interactive `ctl up` | `scripts/common/_select.sh` |
| `dev/host.sh` | `ctl dev` — ensure data core (if any) + run apps on host (`process-compose` or bash fallback) | `scripts/dev/host.sh` |
| `dev/migrate.sh` | `ctl migrate {up\|down\|new\|status}` — Alembic | `scripts/dev/migrate.sh` |
| `dev/test.sh` | `ctl test [backend\|frontend]` — pytest + bun test | `scripts/dev/test.sh` |
| `dev/lint.sh` | `ctl lint [backend\|frontend]` — ruff + biome (stack-specific; adapt or drop) | `scripts/dev/lint.sh` |
| `container/up.sh` | `ctl up` — interactive 2-axis: standalone config (replaces base) + `.m.` modifiers; plan + `--list` + `--attach` + `--nqa`/`-y` | `scripts/container/up.sh` |
| `container/build.sh` / `container/clean.sh` | `ctl build` / `ctl clean [-y]` | `scripts/container/{build,clean}.sh` |
| `container/health.sh` | `ctl health [svc…]` — one-shot health table | `scripts/container/health.sh` |
| `container/shell.sh` | `ctl shell <svc>` — psql / redis-cli / shell in a container | `scripts/container/shell.sh` |
| `container/ps.sh` | `ctl ps` — containers, then host dev processes (resolved by dev port → PID) | `scripts/container/ps.sh` |
| `config/setup.sh` | `ctl setup` — `.env` wizard (generates `*_PASSWORD/_SECRET/_KEY`), data dirs, installs deps | `scripts/config/setup.sh` |
| `config/status.sh` | `ctl status` — doctor: env · runtimes (mise+pins, uv/bun/uvenv) · docker · deps · health · stack | `scripts/config/status.sh` |
| `config/check-env.sh` | `.env` vs `.env.example` schema diff (helper; used by status) | `scripts/config/check-env.sh` |

### `claude/`

| File | What it is | Drops at |
|---|---|---|
| `CLAUDE.md.template` | Agent-facing brief template | `CLAUDE.md` at repo root |

## Conventions

- File names mirror their **drop name** where possible (`compose.m.expose.yaml`, not `compose-expose.yaml`).
- Templates use `<PROJECT>` / `<placeholder>` markers the slash command substitutes.
- All snippets are **illustrative defaults** — adapt per project. The category structure is the contract; the specific values are not.
- Image tags and runtime versions are illustrative — see the `references/3-app/04-database/` and `references/2-repo/06-runtime-environment/01_mise.md` notes about checking latest and asking the user.

## What's NOT here

This folder is intentionally small. Things deliberately not snippeted:

- **A full project tree** — see `references/2-repo/01-layouts/` instead
- **ML training scripts** — too project-specific; see `references/2-repo/07-ml-orchestration/`
- **Backend `pyproject.toml`** — see `references/3-app/02-backend/00_app-skeleton.md` for the shape
- **`Dockerfile`s for backend/frontend** — too stack-specific; the references cover the patterns
- **Cloud orchestrator configs** — cloud GPU work uses thin `scripts/cloud/` wrappers over the provider CLI; see `references/2-repo/07-ml-orchestration/`

If you find yourself wanting a snippet that isn't here, ask: does it have a small focused job and apply to most projects of its layout? If yes, add it. If no, leave it as a reference example.
