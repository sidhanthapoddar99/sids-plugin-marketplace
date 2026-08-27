# Environment — where a value lives and who reads it

Three files. Nothing else stores configuration.

| File | Where | Holds | Committed |
|---|---|---|---|
| `.env.example` | root | The contract. Every key the stack needs, with comments. Secrets blank, non-secrets with their dev value. | yes |
| `.env` | root, and one per frontend | The filled contract for this machine or this host. A frontend's `.env` holds only `VITE_*` / `NEXT_PUBLIC_*` keys. | no |
| `config.yaml` | each backend | All settings of that backend. Secrets and connection values enter as `${VAR}`. Everything else is a literal default. | yes |

Template: `assets/env/env.example.template`.

## How a value flows

1. `.env` is loaded into the environment. Loaders never overwrite a variable that is already set (`override=False`, skip-if-set). Never `source .env`.
2. `config.yaml` is read. Every `${VAR}` resolves from the environment. A literal stays as written.
3. A `${VAR}` that is not set fails at startup. The app never runs on a guessed secret.

One module per backend does all three steps: `config.py`, `config.rs`, `config.go`, or `config.ts`. It loads `.env`, parses `config.yaml`, resolves `${VAR}`, validates the result into a typed settings object, and fails on a missing variable. The rest of the app imports that object. Nothing else calls `os.environ` or reads a file. Snippets: `assets/config/`.

So `config.yaml` is the single place that names every variable a backend reads. Read it to know what a backend needs. `.env.example` is the single place that names every variable the stack needs.

```yaml
database:
  url: ${DATABASE_URL}     # from .env, must be set
  pool_size: 20            # literal default, lives here
server:
  host: ${API_HOST}        # from .env, differs dev vs prod
  port: ${API_PORT}
```

Dev, CI and prod use the same `config.yaml`. Only the environment differs: a filled `.env` on a dev machine, the CI secret store, a filled `.env` on the prod host (`chmod 600`) or the container's `environment:`.

## What goes where

| Value | Home | Example |
|---|---|---|
| Generated secret | `.env` | `JWT_SIGNING_KEY`, `ENCRYPTION_KEY_*`, `POSTGRES_PASSWORD` |
| Third-party credential | `.env` | `GOOGLE_CLIENT_SECRET`, `S3_SECRET_KEY`, `SMTP_PASSWORD` |
| Connection leaf and composed URL | `.env` | `POSTGRES_HOST`, `POSTGRES_PORT`, `DATABASE_URL=postgres://${POSTGRES_USER}:…` |
| Internal service endpoint | `.env` | `API_HOST`, `API_PORT`, `API_URL` |
| Public origin | `.env` | `PLATFORM_PUBLIC_URL` |
| Route prefix | `.env` | `API_PREFIX=/api`, `WS_PREFIX=/ws` |
| Compose plumbing | `.env` | `DATA_DIR`, `BACKUP_DIR`, `FRONTEND_PORT` |
| Backend behaviour | `config.yaml` | pool size, TTLs, feature flags, file paths. Literals. |
| Frontend public value | `apps/<frontend>/.env` | `VITE_API_URL`, `VITE_APP_NAME`. Public by definition. |

A secret never appears in `config.yaml` as a literal. A host name that differs between dev and prod (`localhost` vs the compose service name) lives in `.env`, so prod is a different `.env`, not a different `config.yaml`.

## Secret classes

| Class | Generate with | Rotation |
|---|---|---|
| Signing key (JWT) | `openssl rand -hex 32` | On leak. Rotating invalidates all tokens. |
| Encryption key at rest | `openssl rand -hex 32` | Never without a re-encrypt migration. |
| Service password (Postgres, Redis, S3) | `openssl rand -base64 24 \| tr -d '+/=' \| head -c 24` | Yearly, or on leak. |
| Third-party credential | The provider's console | On leak. |

Shared keys are one variable. If Python and Rust validate the same JWT, both read `JWT_SIGNING_KEY`. Keys that are not shared are separate variables (`ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`).

`ctl setup` copies `.env.example` to `.env` and fills empty `*_KEY` and `*_PASSWORD` values. See `05_ctl.md`.

## Frontend rule

A frontend has its own `.env` and `.env.example` in its folder. Every key in it is `VITE_*` / `NEXT_PUBLIC_*`, and every such key ends up in the bundle, readable by anyone. So a frontend `.env` holds only public values. Never a secret. A frontend that needs a credential calls the backend that holds it. AI keys follow the same rule: backend only, behind a proxy route.

The dev proxy in `vite.config.ts` mirrors the production edge. The browser talks to its own origin in both. No CORS.

## How Docker consumes these

| Way | When the value is read | Used for | Compose key |
|---|---|---|---|
| Build-time | During `docker build`. Baked into the image. | Frontend `VITE_*` keys, because `vite build` reads them. | `build.args` from the frontend `.env` |
| Runtime | When the container starts. One image serves every environment. | Backends. `env_file: .env` fills the environment; `config.yaml` resolves `${VAR}` from it. | `env_file`, `environment` |

Secrets are runtime only. A build arg stays in the image history.

Keep the frontend bundle free of per-environment values. It talks to its own origin (`/api`), and the edge routes. Then no `VITE_*` value differs between dev and prod, and one image serves both.

Production compose (`compose.prod.yaml`) sets literally the values that the compose network itself decides: `API_HOST=api`, `POSTGRES_HOST=postgres`, the nginx upstream `api:8000`. These are service names, not choices. Compose `environment:` beats `env_file`, so they win over the dev `localhost` in `.env` without editing `.env`. Passwords, keys and public URLs still come from `.env`.

Rule: a value is fixed in compose when the compose file decides it. It comes from `.env` when the host or the operator decides it. Compose file shapes: `05_ctl.md`.

## `.env.example` rules

- Every key present. A comment says who consumes it and, for hosts, the prod value.
- Secrets blank. Non-secrets carry the dev default.
- Composed values use `${VAR}` from leaves, so a host change is one edit.
- Grouped by service. Future services stay as commented blocks.
- Never read `.env` when auditing. Read `.env.example`.
