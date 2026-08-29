# Env — `.env`, `.env.example`, `config.yaml`, `config.local.yaml`

Five files. Nothing else stores configuration. Template: `template/.env.example`, `template/apps/api/config.yaml`, `template/apps/multi-web-app/app/.env.example`.

| File | Where | Holds | Read by | Committed |
|---|---|---|---|---|
| `.env.example` | root | The contract. Every key the stack needs, with a comment naming the consumer. Secrets blank, non-secrets with the dev value. | humans, `ctl check` | yes |
| `.env` | root | Every secret. Every host, port, prefix and path. The one place. | `ctl`, compose, backend loaders | no |
| `config.yaml` | each backend | All settings of that backend. `${VAR}` for secrets and endpoints. Literals for defaults. | the backend's loader | yes |
| `config.local.yaml` | each backend | A developer's overrides of literals. Never a secret. | the backend's loader | no |
| `.env` / `.env.example` | each frontend | Build constants only: `VITE_*`, `NEXT_PUBLIC_*`, `PUBLIC_*`. Public by definition. | the frontend's dev server; `ctl build` as build args | example yes, `.env` no |

## Rules

1. **Every secret lives in the root `.env`.** Only backend services read it. A client-facing app never does. One exception: a Next.js server that proxies or runs its own routes reads server-only keys from it.
2. **Compose and `ctl` read only the root `.env`.** Never an app's `.env` or `config.yaml`. One exception: `ctl build` forwards each frontend's `.env` as build args, without interpreting it.
3. **Everything runs from the repo root.** `ctl` calls compose with `--project-directory <root>`. Every path in `.env` and in every compose file is root-relative: `./data`, `./apps/api`. Never `../`. `ctl check` fails on it.
4. **A value lives in exactly one file**, chosen by who reads it. Compose, `ctl` or a backend → root `.env`. A frontend dev server → its own `.env`. A backend default → `config.yaml`.
5. **Backend precedence:** process env > `config.local.yaml` > `config.yaml`. A real environment variable always wins.
6. **The frontend bundle carries no environment value.** The API is on the same origin, so no URL is needed. See `03_setup.md`.
7. **Never read `.env` when auditing. Read `.env.example`.**

## How a backend reads a value

One module per backend does it all: `config.py`, `config.rs`, `config.go`, `config.ts`. Nothing else reads the environment or a file. Template: `template/apps/api/app/config.py`, `template/apps/engine/src/config.rs`.

1. Find the repo root: walk up to the folder that holds `ctl`. Load `<root>/.env` skip-if-set. Under docker there is no file; compose already set the environment, so this step does nothing.
2. Read `config.yaml`. Deep-merge `config.local.yaml` over it if present.
3. Replace every `${VAR}` from the environment. An unset `${VAR}` fails at startup and names the key. The app never runs on a guessed value.
4. Validate into one typed settings object. The app imports that object.

```yaml
database:
  url: ${DATABASE_URL}     # from .env, must be set
  pool_size: 20            # literal default. Override in config.local.yaml
engine:
  url: ${ENGINE_URL}       # http://localhost:8080 under ctl dev; http://engine:8080 under docker
```

So `config.yaml` names every variable a backend reads. `.env.example` names every variable the stack reads. Together they are the full inventory.

## How a frontend reads a value

Mostly it does not.

| Mode | Source |
|---|---|
| `ctl dev` | `apps/<group>/<name>/.env` for build constants. The dev proxy target (`API_PORT`) comes from the process env, which `ctl dev` filled from the root `.env`. Never a `VITE_*` key. |
| `ctl build` | The same file, forwarded as `build.args`. Baked into the bundle. |
| running container | Nothing for a static build. A Next.js server gets `API_HOST`, `API_PORT` from compose `environment:`. |

Every `VITE_*` / `NEXT_PUBLIC_*` / `PUBLIC_*` key ends up in the bundle, readable by anyone. A frontend that needs a credential calls the backend that holds it. AI keys: backend only, behind a proxy route.

## How Docker consumes `.env`

| Way | When read | Used for |
|---|---|---|
| Build-time `build.args` | During `ctl build`. Baked into the image. | Frontend build constants only. |
| Runtime `environment:` | When the container starts. | Backends, the Next.js server, the edge. Every secret. |

Secrets are runtime only. A build arg stays in the image history.

`compose.base.yaml` has no `env_file`. Each service lists exactly the keys it reads: `${VAR}` when the operator decides the value (secrets, ports, prefixes), a literal when compose decides it (service names). Read the file and you know everything a container gets.

## What goes where

| Value | Home | Example |
|---|---|---|
| Generated secret | `.env` | `JWT_SIGNING_KEY`, `ENCRYPTION_KEY_*`, `POSTGRES_PASSWORD` |
| Third-party credential | `.env` | `GOOGLE_CLIENT_SECRET`, `S3_SECRET_KEY` |
| Connection leaf and composed URL | `.env` | `POSTGRES_HOST`, `DATABASE_URL=postgresql://${POSTGRES_USER}:…` |
| Backend endpoint another backend calls | `.env` | `ENGINE_URL` |
| Prefix and dev port | `.env` | `API_PREFIX=/api`, `WEB_APP_PORT=5173` |
| Public origin | `.env` | `PUBLIC_URL` |
| Compose plumbing | `.env` | `DATA_DIR`, `REGISTRY`, `TAG`, `HTTP_PORT` |
| Backend behaviour | `config.yaml` | pool size, TTLs, feature flags, log level |
| A developer's tweak of the above | `config.local.yaml` | `log.level: debug` |
| Frontend build constant | `apps/<group>/<name>/.env` | `VITE_BASE_PATH=/app`, `VITE_APP_NAME` |

A host name that differs between dev and docker (`localhost` vs `api`) lives in `.env` for dev and as a literal in compose for docker. Same `config.yaml`, same `.env`, no edit between modes.

## Secret classes

| Class | Generate with | Rotation |
|---|---|---|
| Signing key (JWT) | `openssl rand -hex 32` | On leak. Invalidates all tokens. |
| Encryption key at rest | `openssl rand -hex 32` | Never without a re-encrypt migration. |
| Service password (Postgres, Redis, Neo4j) | `openssl rand -base64 24 \| tr -d '+/=' \| head -c 24` | Yearly, or on leak. |
| Third-party credential | The provider's console | On leak. |

Shared keys are one variable: Python and Rust validating the same JWT both read `JWT_SIGNING_KEY`. Keys not shared are separate: `ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`. `ctl setup` fills every blank `*_KEY` and `*_PASSWORD`.

## `.env.example` rules

- Every key present. A comment names the consumer and, for hosts, the docker value.
- Secrets blank. Non-secrets carry the dev default.
- Composed values use `${VAR}` from leaves, so a host change is one edit.
- Grouped by consumer. Future services stay as commented blocks.
- `ctl check` verifies every `${VAR}` in every `config.yaml` is a key here, and that no `config.yaml` holds a secret literal.
