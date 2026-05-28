# Snippets

Fragments the `project-setup` skill cites and `/ps-setup` can drop into a new or existing project. **Not** a full project template — focused pieces grouped by domain.

## Layout

```
assets/snippets/
├── frontend/          # CSS tokens, theme wiring, vite config
├── docker/            # compose overlays per deployment mode
├── infra/             # config baked into containers (nginx)
├── python/            # alembic helpers + shim template
├── env/               # .env.example + .mise.toml templates
├── scripts/           # ctl dispatcher
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

| File | What it is | Drops at |
|---|---|---|
| `compose.yaml` | Base — services declared, no host ports, internal network | `docker/compose.yaml` |
| `compose.database-only.yaml` | Standalone postgres + redis (dev mode A: apps on host) | `docker/compose.database-only.yaml` |
| `compose.dev.yaml` | Overlay — adds host port exposure | `docker/compose.dev.yaml` |
| `compose.prod.yaml` | Overlay — production (images, resource limits) | `docker/compose.prod.yaml` |
| `compose.traefik.yaml` | Overlay — external Traefik network + labels | `docker/compose.traefik.yaml` |
| `compose.no-ports.yaml` | Overlay — removes host ports (behind external proxy) | `docker/compose.no-ports.yaml` |

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

| File | What it is | Drops at |
|---|---|---|
| `dev-wrapper.sh` | `ctl` control dispatcher (dev/prod/up/down/status/setup/migrate), executable | `ctl` at repo root (rename, chmod +x) |

### `claude/`

| File | What it is | Drops at |
|---|---|---|
| `CLAUDE.md.template` | Agent-facing brief template | `CLAUDE.md` at repo root |

## Conventions

- File names mirror their **drop name** where possible (`compose.dev.yaml`, not `compose-dev.yaml`).
- Templates use `<PROJECT>` / `<placeholder>` markers the slash command substitutes.
- All snippets are **illustrative defaults** — adapt per project. The category structure is the contract; the specific values are not.
- Image tags and runtime versions are illustrative — see the `references/architecture/database/` and `references/repo-setup/mise.md` notes about checking latest and asking the user.

## What's NOT here

This folder is intentionally small. Things deliberately not snippeted:

- **A full project tree** — see `references/repo-setup/layouts/` instead
- **ML training scripts** — too project-specific; see `references/architecture/ml-orchestration/`
- **Backend `pyproject.toml`** — see `references/architecture/backend/pyproject-uv-sync-for-apps.md` for the shape
- **`Dockerfile`s for backend/frontend** — too stack-specific; the references cover the patterns
- **Cloud orchestrator configs** (`*.dstack.yml`, `sky/*.yaml`) — examples live in `references/architecture/ml-orchestration/`

If you find yourself wanting a snippet that isn't here, ask: does it have a small focused job and apply to most projects of its layout? If yes, add it. If no, leave it as a reference example.
