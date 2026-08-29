# Env — three env files, `config.yaml`, `config.local.yaml`

Configuration lives in five kinds of file. Nothing else stores it. Template: `template/.env.*.template`, `template/apps/example-api-python/config.yaml`.

| File | Where | Holds | Read by | Committed |
|---|---|---|---|---|
| `.env.secrets` | root | Every secret: passwords, signing and encryption keys, third-party credentials. The database connection values built from them. `REGISTRY`, `TAG`. | compose, backend loaders | no. `.env.secrets.template` yes, every value blank |
| `.env.data` | root | Every path: `DATA_DIR`, `LOGS_DIR`, `BACKUP_DIR`, dataset paths. Root-relative. | compose, `ctl`, apps that touch disk | no. `.env.data.template` yes |
| `.env.proxy` | root | The service definitions. Per proxied piece (backend, server frontend): `<PIECE>_HOST`, `_PORT`, `_PREFIX`; backends add `_URL`. Per static frontend: `_PORT`, `_PREFIX` only (it is built in, never proxied). The piece that owns `/` has no `_PREFIX`. Plus `PUBLIC_URL`, `HTTP_PORT`, `HTTPS_PORT`, `DEV_PROXY_PORT`, `COMPOSE_PROJECT_NAME`, external service URLs. | the service itself (binds `_PORT`, mounts `_PREFIX`), `ctl`, compose, nginx templates, Vite/Next configs, other backends | no. `.env.proxy.template` yes |
| `config.yaml` | each backend | All settings of that backend. `${VAR}` for secrets and endpoints. Literals for defaults. | the backend's loader | yes |
| `config.local.yaml` | each backend | A developer's overrides of literals. Never a secret. | the backend's loader | no |

A frontend has no env file. Its prefix reaches it from `.env.proxy` through compose (build arg) or the process env (dev server), under the same key (`WEB_APP_PREFIX`), read directly by the framework config with no `VITE_*` alias and no literal fallback: a missing key throws. A display name is a literal in the framework config.

## Rules

1. **One value, one file, chosen by what it is.** A secret → `.env.secrets`. A path → `.env.data`. A host, port, prefix or URL of a piece the edge routes → `.env.proxy`. A backend default → `config.yaml`. `ctl check` enforces the key-name patterns per file.
   Database endpoints (`POSTGRES_HOST`, `REDIS_HOST`, `NEO4J_HOST` and their ports and URLs) are connection values, not routes: nothing proxies them and no frontend ever sees them. They live in `.env.secrets` next to the password they pair with. That is also what lets the same file point at a hosted engine (RDS, ElastiCache): change the host and password there, and nothing else in the repo changes.
2. **Only backends and compose read `.env.secrets`.** A frontend never does. One exception: a Next.js server that proxies or runs its own routes reads server-only keys from it.
3. **`.env.proxy` defines a service, not only its route.** `<PIECE>_PORT` is the port the service binds on the host (`uvicorn --port ${API_PORT}`, `vite --port $WEB_APP_PORT`); `<PIECE>_PREFIX` is where it mounts its routes (`FastAPI(root_path=settings.server.prefix)`). The edge and the dev proxy read the same keys to route. One key, two readers: a service and its route cannot disagree. Never a port or prefix typed into code or a framework config, and never a literal fallback (`?? "/api"`): a missing key fails. Under docker the internal port is compose's decision (`API_PORT: 8000` as a literal, `api:8000` as the upstream); `.env.proxy` ports are host-side.
4. **Everything in `.env.proxy` may end up in a bundle.** Treat every key as public. No secret, ever.
5. **Compose and `ctl` read only the three root files.** Never an app's file. `ctl` passes them as `--env-file secrets, data, proxy` on every compose call; compose reads no `.env` on its own.
6. **Everything runs from the repo root.** `ctl` calls compose with `--project-directory <root>`. Every path in `.env.data` and in every compose file is root-relative: `./data`, `./apps/…`. Never `../`.
7. **Backend precedence:** process env > `config.local.yaml` > `config.yaml`. A real environment variable always wins. The loader reads the three files skip-if-set. Two channels reach a literal from the environment: `${VAR}` in `config.yaml` for values the file names, and the nested override `<APP>__<SECTION>__<KEY>` (`API__DATABASE__POOL_SIZE`) for any literal, which is how a container or CI tweaks one setting without a file.
8. **Templates are the contract.** Every key present, every secret blank, a comment per key naming the reader and how the value is made. `ctl setup` copies template → file and fills the generated secrets. Never read a filled file when auditing. Read the templates.

## How a backend reads a value

One module per backend does it all: `config.py`, `config.rs`, `config.go`, `config.ts`. Nothing else reads the environment or a file. Template: `template/apps/example-api-python/app/config.py`.

1. Find the repo root: walk up to the folder that holds `ctl`. Load `.env.secrets`, `.env.data`, `.env.proxy` from it, skip-if-set. Under docker the files are absent; compose already set the environment, so this step does nothing. Skip-if-set is the point: `set -a; source .env` would let a file beat an inline override (`HTTP_PORT=8085 ctl up`) or a CI-injected secret. The price is plain `KEY=value` lines only: no multi-line values, no command substitution.
2. Read `config.yaml`. Deep-merge `config.local.yaml` over it if present: nested maps merge key by key, arrays replace whole.
3. Replace every `${VAR}` from the environment. An unset `${VAR}` fails at startup and names the key. The app never runs on a guessed value.
4. Validate into one typed settings object. The app imports that object.

```yaml
database:
  url: ${DATABASE_URL}     # .env.secrets, must be set
  pool_size: 20            # literal default. Override in config.local.yaml
engine:
  url: ${ENGINE_URL}       # .env.proxy: http://localhost:8080 under ctl dev; compose sets http://engine:8080
```

So `config.yaml` names every variable a backend reads, and the three templates name every variable the stack reads. Together they are the full inventory.

## How a frontend reads a value

It has no env file. It needs one value, its prefix, and gets it from `.env.proxy`:

| Mode | How |
|---|---|
| `ctl dev` | `ctl` exports the three files; `vite.config.ts` reads `process.env.WEB_APP_PREFIX` for `base` and `API_PORT` for the proxy target. Never a `VITE_*` key, never a fallback. |
| `ctl build` | compose passes `VITE_BASE_PATH: ${WEB_APP_PREFIX}` as a build arg, interpolated from `.env.proxy`. Baked into the bundle. |
| running container | Nothing for a static build. A Next.js server gets `API_HOST`, `API_PORT` from compose `environment:`. |

The API location is never a frontend value. Same origin, `fetch("/api/…")`. A frontend that needs a credential calls the backend that holds it. AI keys: `.env.secrets`, backend only, behind a proxy route.

## How Docker consumes the files

| Way | When read | Used for |
|---|---|---|
| Build-time `build.args` | During `ctl build`. Baked into the image. | Prefixes from `.env.proxy`. Nothing from `.env.secrets`, ever: a build arg stays in image history. |
| Runtime `environment:` | When the container starts. | Backends, the Next.js server, the edge. Every secret. |

`compose.base.yaml` has no `env_file`. Each service lists exactly the keys it reads: `${VAR}` when the operator decides the value, a literal when compose decides it (service names: `api`, `postgres`). Read the file and you know everything a container gets.

Under docker, `<PIECE>_HOST` in `.env.proxy` is not consulted: compose sets the service name as a literal. `ctl up +env_override` reverses that for a piece running outside this compose. See `03_setup.md`.

## Secret classes

| Class | Generate with | Rotation |
|---|---|---|
| Signing key (JWT) | `openssl rand -hex 32` | On leak. Invalidates all tokens. |
| Encryption key at rest | `openssl rand -hex 32` | Never without a re-encrypt migration. |
| Service password (Postgres, Redis, Neo4j) | `openssl rand -base64 24 \| tr -d '+/=' \| head -c 24` | Yearly, or on leak. |
| Third-party credential | The provider's console | On leak. |

`ctl setup` generates every blank `*_PASSWORD`, `*_KEY`, `*_SECRET` in `.env.secrets`, and on later runs appends any key the template gained; `ctl status` diffs each file against its template. Third-party credentials stay blank until pasted. A secret that ever reaches git is rotated, not deleted: history is forever. Every secret class has a written recovery step, not only a cadence. Shared keys are one variable (`JWT_SIGNING_KEY` for Python and Rust); keys not shared are separate (`ENCRYPTION_KEY_PYTHON`, `ENCRYPTION_KEY_RUST`).

## Template rules

- Every key present. A header names the file's purpose, its readers, and how `ctl setup` turns it into the real file.
- Every key carries a comment: who reads it, and for a secret how it is generated, and for a host its docker value.
- Secrets blank. Non-secrets carry the dev default.
- Composed values use `${VAR}` from leaves (`DATABASE_URL=postgresql://${POSTGRES_USER}:…`), so a host change is one edit.
- Grouped by piece. A future integration stays as a commented block.
- `.gitignore`: `.env`, `.env.*`, `!.env.*.template`.

## `ctl check` on env

- every `${VAR}` in every `config.yaml` is a key in one of the three templates
- a key ending `_PASSWORD`, `_KEY`, `_SECRET` appears only in `.env.secrets.template`
- every key in `.env.proxy.template` ends `_HOST`, `_PORT`, `_PREFIX`, `_URL` (plus `PUBLIC_URL`, `HTTP_PORT`, `HTTPS_PORT`, `DEV_PROXY_PORT`, `COMPOSE_PROJECT_NAME`)
- every key in `.env.data.template` ends `_DIR`
- no secret literal in any `config.yaml`; no tracked `config.local.yaml`; no tracked `.env.*` except templates
