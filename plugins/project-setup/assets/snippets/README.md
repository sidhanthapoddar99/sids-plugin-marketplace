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

Three axes: `compose.yaml` is the profiled base (data core = no profile; apps `[app]`/`[edge]`); `compose.prod.yaml` is the one `--config=prod` deployment config; `compose.m.<name>.yaml` files are stackable `.m.` modifiers (`--expose`, `--traefik`). `ctl up [profile…] [--config=prod] [--<modifier>…]` assembles them. Full convention: `references/repo-setup/runtime/docker-compose-structure.md`.

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

`dev-wrapper.sh` drops at the repo root as `ctl`; **every other file drops into `scripts/`**. `ctl` is a thin router — it owns arg routing, the `ctl up` compose assembly (profiles + one `--config` + `.m.` modifiers), and trivial `docker compose` passthroughs; each command with a real body lives in its own self-contained `scripts/<cmd>.sh`. See `references/repo-setup/runtime/script-overview.md` (model + script map) and `.../script-usage.md` (commands).

| File | What it is | Drops at |
|---|---|---|
| `dev-wrapper.sh` | `ctl` dispatcher — routes `dev`/`up`/`down`/`ps`/`logs`/`setup`/`status`/`migrate`/`test`/`build`/`clean`, executable | `ctl` at repo root (rename, chmod +x) |
| `dev-host.sh` | host dev loop — bash fallback (≤2 procs; else `process-compose`), runs uvicorn + `bun dev` | `scripts/dev-host.sh` |
| `setup.sh` | `ctl setup` — `.env` wizard: copies `.env.example`, generates `*_PASSWORD/_SECRET/_KEY` | `scripts/setup.sh` |
| `status.sh` | `ctl status` — config doctor (env schema + tools + data-core health) | `scripts/status.sh` |
| `check-env.sh` | diff `.env` keys against `.env.example` (called by `status.sh`) | `scripts/check-env.sh` |
| `migrate.sh` | `ctl migrate {up\|down\|new\|status}` — Alembic | `scripts/migrate.sh` |
| `wait-for-health.sh` | poll compose services until healthy (used by `ctl dev`) | `scripts/wait-for-health.sh` |
| `test.sh` / `build.sh` / `clean.sh` | `ctl test` / `build` / `clean` workers | `scripts/{test,build,clean}.sh` |

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
