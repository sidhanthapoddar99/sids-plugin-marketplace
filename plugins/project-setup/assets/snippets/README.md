# Snippets

Fragments the `project-setup` skill cites and `/ps-setup` can drop into a new or existing project. **Not** a full project template — focused pieces grouped by domain.

## Layout

```
assets/snippets/
├── frontend/          # CSS tokens, theme wiring, vite config
├── docker/            # profiled compose base + --config + .m. modifiers
├── infra/             # config baked into containers (nginx)
├── python/            # alembic helpers + shim template
├── env/               # .env.example + .mise.toml templates
├── scripts/           # thin ctl dispatcher + self-contained worker scripts
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

Three axes: `compose.yaml` is the profiled base (data core = no profile; apps `[app]`/`[edge]`); `compose.prod.yaml` is the one `--config=prod` deployment config; `compose.m.<name>.yaml` files are stackable `.m.` modifiers (`--expose`, `--traefik`). `ctl up [profile…] [--config=prod] [--<modifier>…]` assembles them. Full convention: `references/repo-setup/runtime/docker-overview.md`.

| File | What it is | Drops at |
|---|---|---|
| `compose.yaml` | Profiled base — all services, no host ports; data core has no profile, apps `[app]`/`[edge]` | `docker/compose.yaml` |
| `compose.prod.yaml` | `--config=prod` config — image tags, resource limits, `.env.production` | `docker/compose.prod.yaml` |
| `compose.m.expose.yaml` | `--expose` modifier — publish host ports (`ctl dev` layers it for the data core) | `docker/compose.m.expose.yaml` |
| `compose.m.traefik.yaml` | `--traefik` modifier — external Traefik network + labels on the edge | `docker/compose.m.traefik.yaml` |

### `infra/`

| File | What it is | Drops at |
|---|---|---|
| `nginx.conf` | Routes `/api/*` to backend container, serves SPA, handles `/ws/*` | `infra/nginx/nginx.conf` |

### `python/`

| File | What it is | Drops at |
|---|---|---|
| `alembic-shim.py` | Three-file revision pattern shim (atheneum-style) | `apps/backend/alembic/versions/<rev>.py` (per migration) |
| `alembic_helpers.py` | `run_sql` helper imported by the shim | `apps/backend/alembic_helpers.py` |

### `env/`

| File | What it is | Drops at |
|---|---|---|
| `env.example.template` | `.env.example` with categories + `openssl rand` instructions | `.env.example` at repo root |
| `mise.toml.example` | `.mise.toml` template (versions illustrative) | `.mise.toml` at repo root |

### `scripts/`

**This is a template, not a fixed spec.** It's a sensible default toolkit — copy `ctl` (to the repo root, `chmod +x`, no extension — it's the public API) **and the whole `scripts/` folder**, then add / remove / edit commands to fit the project. Most repos won't need every command shipped here; some (`lint`, `shell`) are stack-specific — adapt or drop them.

`ctl` is a thin router; `scripts/_lib.sh` is the shared foundation (colors, uniform `--help`, `dc()` + discovery, guards, health) every worker sources; each command with a real body is a worker named **`scripts/<category>-<name>.sh`** (category ∈ `dev` | `docker` | `manage` — the `ctl` verb stays clean: `ctl migrate`, file `dev-migrate.sh`). Trivial `docker compose` forwards (`down`/`restart`/`logs`/`ps`/`exec`) stay inline in `ctl`. Colors auto-disable when piped or `NO_COLOR` is set; every command takes `-h`/`--help`.

**To add a command:** drop `scripts/<category>-<name>.sh` (use the worker preamble in `_lib.sh`) and wire one `run <file>` line into `ctl`'s `case`. See `references/repo-setup/runtime/script-overview.md` (model + map) and `.../script-usage.md` (commands).

| File | What it is | Drops at |
|---|---|---|
| `ctl` | dispatcher — routes every subcommand, inlines trivial compose forwards, executable | `ctl` at repo root (chmod +x) |
| `_lib.sh` | **shared foundation** sourced by `ctl` + all workers (colors, `print_help`, `dc()`+discovery, guards, health, `confirm`) | `scripts/_lib.sh` |
| `dev-host.sh` | `ctl dev` — ensure data core + run apps on host (`process-compose` or bash fallback) | `scripts/dev-host.sh` |
| `dev-migrate.sh` | `ctl migrate {up\|down\|new\|status}` — Alembic | `scripts/dev-migrate.sh` |
| `dev-test.sh` | `ctl test [backend\|frontend]` — pytest + bun test | `scripts/dev-test.sh` |
| `dev-lint.sh` | `ctl lint [backend\|frontend]` — ruff + biome (stack-specific; adapt or drop) | `scripts/dev-lint.sh` |
| `docker-up.sh` | `ctl up` — assemble profiles + one `--config` + `.m.` modifiers (`--dry-run`) | `scripts/docker-up.sh` |
| `docker-build.sh` / `docker-clean.sh` | `ctl build` / `ctl clean [-y]` | `scripts/docker-{build,clean}.sh` |
| `docker-health.sh` | `ctl health [svc…]` — one-shot health table | `scripts/docker-health.sh` |
| `docker-shell.sh` | `ctl shell <svc>` — psql / redis-cli / shell in a container | `scripts/docker-shell.sh` |
| `manage-setup.sh` | `ctl setup` — `.env` wizard (generates `*_PASSWORD/_SECRET/_KEY`) | `scripts/manage-setup.sh` |
| `manage-status.sh` | `ctl status` — doctor: env · runtimes (mise+pins, uv/bun/uvenv) · docker · health · stack | `scripts/manage-status.sh` |
| `manage-check-env.sh` | `.env` vs `.env.example` schema diff (helper; used by status) | `scripts/manage-check-env.sh` |

### `claude/`

| File | What it is | Drops at |
|---|---|---|
| `CLAUDE.md.template` | Agent-facing brief template | `CLAUDE.md` at repo root |

## Conventions

- File names mirror their **drop name** where possible (`compose.m.expose.yaml`, not `compose-expose.yaml`).
- Templates use `<PROJECT>` / `<placeholder>` markers the slash command substitutes.
- All snippets are **illustrative defaults** — adapt per project. The category structure is the contract; the specific values are not.
- Image tags and runtime versions are illustrative — see the `references/architecture/database/` and `references/repo-setup/runtime/mise.md` notes about checking latest and asking the user.

## What's NOT here

This folder is intentionally small. Things deliberately not snippeted:

- **A full project tree** — see `references/repo-setup/layouts/` instead
- **ML training scripts** — too project-specific; see `references/architecture/ml-orchestration/`
- **Backend `pyproject.toml`** — see `references/architecture/backend/pyproject-uv-sync-for-apps.md` for the shape
- **`Dockerfile`s for backend/frontend** — too stack-specific; the references cover the patterns
- **Cloud orchestrator configs** (`*.dstack.yml`, `sky/*.yaml`) — examples live in `references/architecture/ml-orchestration/`

If you find yourself wanting a snippet that isn't here, ask: does it have a small focused job and apply to most projects of its layout? If yes, add it. If no, leave it as a reference example.
