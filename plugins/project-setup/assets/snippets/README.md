# Snippets

Fragments the `project-setup` skill cites and `/ps-setup` can drop into a new or existing project. **Not** a full project template — focused pieces.

## Index

| File | What it is | Where it lands |
|---|---|---|
| `tokens.css` | Design tokens — `--bg-*`, `--fg-*`, `--space-*`, `--radius-*`, light + dark | `apps/<frontend>/src/styles/tokens.css` (or `packages/styles/src/tokens.css`) |
| `globals.css` | Base resets, tailwind directives, shadcn alias map | `apps/<frontend>/src/styles/globals.css` |
| `light-dark.css` | Theme transitions + scrollbar/selection styling | `apps/<frontend>/src/styles/light-dark.css` |
| `dev-wrapper.sh` | `./dev` wrapper template | repo root, renamed to `dev`, `chmod +x` |
| `env.example.template` | `.env.example` with categories and `openssl rand` instructions | repo root, renamed to `.env.example` |
| `mise.toml.example` | `.mise.toml` template | repo root, renamed to `.mise.toml` |
| `compose-base.yaml` | `docker/compose.yaml` — base, no host ports | `docker/compose.yaml` |
| `compose-database-only.yaml` | Standalone postgres + redis | `docker/compose.database-only.yaml` |
| `compose-dev.yaml` | Overlay — adds host ports | `docker/compose.dev.yaml` |
| `compose-prod.yaml` | Overlay — production overrides | `docker/compose.prod.yaml` |
| `compose-traefik.yaml` | Overlay — external Traefik network | `docker/compose.traefik.yaml` |
| `compose-no-ports.yaml` | Overlay — removes host ports | `docker/compose.no-ports.yaml` |
| `vite-proxy.config.ts` | `vite.config.ts` with `/api/*` proxy | `apps/frontend/vite.config.ts` |
| `nginx-api-route.conf` | `nginx.conf` routing `/api/*` to backend, serving SPA | `infra/nginx/nginx.conf` |
| `alembic-shim.py` | Three-file revision pattern shim | `apps/backend/alembic/versions/<name>.py` (template) |
| `alembic_helpers.py` | The `run_sql` helper for the shim | `apps/backend/alembic_helpers.py` |
| `claude-md.template` | `CLAUDE.md` agent brief template | repo root, renamed to `CLAUDE.md` |

## Conventions

- Names in this folder use `-` separators and human-readable extensions (`compose-base.yaml`, `tokens.css`). When dropped into a project, they are renamed to the convention (`compose.yaml`, etc.).
- Templates use `<PROJECT>` / `<placeholder>` placeholders the slash command substitutes.
- All snippets are illustrative defaults — adapt per project. The category structure (sections / token names / file roles) is the contract; the specific values are not.
