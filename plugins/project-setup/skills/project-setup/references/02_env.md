# Env — root `.env`, `config.yaml`, `config.local.yaml`

Configuration has one root environment file and per-backend settings. Template: `template/.env.template`, `template/apps/example-api-python/config.yaml`.

| File | Where | Holds | Read by | Committed |
|---|---|---|---|---|
| `.env` | root | Debugging, service addresses, data paths, secrets and deployment settings, grouped by kind | `ctl`, Compose interpolation, backend loaders | no; `.env.template` yes |
| `config.yaml` | each backend | All settings of that backend. `${VAR}` for secrets and endpoints. Literals for defaults. | backend loader | yes |
| `config.local.yaml` | each backend | Developer overrides of literals. Never a secret. | backend loader | no |

## Rules

1. **One environment contract.** Keep every environment key in the root `.env.template`, with blank secrets and useful non-secret defaults, so an operator can find the whole contract in one place. Group keys by kind with two-line hash comment headers, as shown in the template: debugging, service addresses, data paths, secrets and deployment. Within each section, use single-hash service subheadings such as `# Postgres` and `# Redis`, with one blank line between groups. Keep addresses and prefixes in the service-address section and credentials in the secrets section. Put comments above variables rather than on assignment lines so values are easy to scan and edit. Each setting belongs in one group.
2. **Process inheritance is different from browser exposure.** `ctl` exports the loaded environment to child processes, including frontend dev servers. A dev server can therefore read secrets in its server process. Expose only explicitly selected public constants to browser code. Never serialize or spread `process.env`, use an empty env prefix, or put secrets in `VITE_*`, `NEXT_PUBLIC_*` or `PUBLIC_*` variables that the framework exposes. A root file is not a security boundary between local processes.
3. **Service addresses define both binding and routing.** Use `<PIECE>_HOST`, `_PORT`, `_PREFIX` for each proxied piece; backends may add `_URL`. Static frontends need `_PORT` and `_PREFIX` only. The piece owning `/` has no `_PREFIX`. The service and proxy read the same keys so their routes agree. Missing required values fail instead of using literal fallbacks. Under Docker, Compose decides internal service names and ports (`api:8000`); root `.env` ports control host exposure.
4. **Keep credentials out of browser constants and build args.** Addresses in `.env` are not automatically public, and a URL may contain a password. Browser code calls the same-origin backend route for operations requiring credentials. Only a Next.js server's server-side code may use server credentials.
5. **Load one root file.** `ctl` passes `--env-file <root>/.env` to Compose explicitly. Do not add app env files or depend on Compose discovering one from the current directory, because commands must behave the same from every working directory. Docker services receive declared `environment:` keys, never the whole file via service `env_file:`.
6. **Resolve values before launching consumers.** Paths are root-relative (`./data`, `./logs`) or absolute deployment paths, never `../`. `ctl` anchors Compose with `--project-directory <root>`. Values may reference other keys with `${KEY}`, including later declarations: `BACKUP_DIR=${LOGS_DIR}/backups`. The loader first loads all keys skip-if-set, then resolves references using the winning environment values. It uses text substitution, never `eval`. An unset reference or a cycle fails naming the key. Template: `template/scripts/common/_lib.sh`, `expand_env_refs`.
7. **Preserve backend precedence.** Process environment > `config.local.yaml` > `config.yaml`. Load the root file skip-if-set so inline overrides and CI-injected secrets win, including an explicitly empty value. The nested override `<APP>__<SECTION>__<KEY>` (`API__DATABASE__POOL_SIZE`) overrides literals; `${VAR}` names environment values used in YAML.
8. **Keep defaults in one place.** Do not add `config.<env>.yaml` layers or default forms such as `${VAR:-8000}` in backend settings. An unset reference fails; a literal default belongs in `config.yaml`. Prefix separate databases (`AUTH_DATABASE_URL`, `BILLING_DATABASE_URL`) and nested overrides (`API__`, `ENGINE__`) so services sharing a host do not collide.
9. **Audit the template.** Read `.env.template`, never a filled `.env`, because audit output is a log and the filled file holds live secrets. `ctl setup` copies the template, appends missing keys without replacing existing values, and generates blank local secret keys. `ctl status` compares key names with the template.
10. **The public origin is opt-in.** `PUBLIC_URL`, `HTTP_PORT` and `HTTPS_PORT` ship commented out. Local Docker publishes the edge on the port of the piece owning `/`. A public deployment enables these three keys and uses `ctl up +public`, which refuses blank values. Keep `PUBLIC_URL` out of required YAML references: an app that creates absolute URLs reads it from the process environment and treats absence as relative URLs only. Template: `template/docker/compose.m.public.yaml`.

## How a backend reads a value

One module per backend owns settings: `config.py`, `config.rs`, `config.go` or `config.ts`. Other modules import its typed settings object. Template: `template/apps/example-api-python/app/config.py`, `template/apps/example-engine-rust/crates/common/src/config.rs`.

1. Find the repo root by walking up to `ctl`. Load raw `.env` values skip-if-set using the parser contract below. Resolve references only after all keys are loaded, with the same semantics as rule 6, so forward references cannot become empty strings during parsing. Under `ctl`, values are already resolved; under Docker, the file is absent and Compose supplies declared keys.
2. Read `config.yaml`. Deep-merge `config.local.yaml` if present: maps merge by key, arrays replace whole.
3. Replace `${VAR}` from the environment. Fail on an unset reference. Apply nested environment overrides last so process values win.
4. Validate into one typed settings object.

The root loader accepts unquoted `KEY=value` lines only. It tolerates CRLF and trailing whitespace comments. Quotes stay literal; multi-line values and shell commands are unsupported. Do not source the file, because sourcing executes text and overrides existing values.

## How a frontend reads a value

A frontend has no env file of its own. Its framework config reads selected keys from the process environment; it does not forward that environment to the browser.

| Mode | How |
|---|---|
| `ctl dev` | The dev server inherits the root environment. `vite.config.ts` selects `WEB_APP_PREFIX` for `base` and `API_PORT` for its server-side proxy. |
| `ctl build` | Compose selects public prefixes for build args, for example `VITE_BASE_PATH: ${WEB_APP_PREFIX}`. The prefix is baked into the bundle. |
| Running container | Static builds read nothing. A Next.js server receives only its declared server keys through Compose `environment:`. |

Never use a `VITE_API_URL` alias or an API host in the bundle: browser requests use the same origin, such as `fetch("/api/…")`. If a project needs a browser debugging flag, select that one non-secret value explicitly in the framework config.

## How Docker consumes the file

| Way | When read | Used for |
|---|---|---|
| CLI `--env-file` | Compose model interpolation | Values referenced by the Compose model, overridden by the process environment |
| `build.args` | Image build | Explicitly selected public constants only; secrets persist in image history if passed here |
| `environment:` | Container start | Exactly the runtime keys each service declares, including backend credentials |

`template/docker/compose.base.yaml` has no service `env_file:`. Each service declares `${VAR}` when the operator decides the value and a literal when Compose decides it, such as `api` or `postgres`. Under Docker, host-side `<PIECE>_HOST` is unused unless `+env_override` selects it for an external service. See `03_routing.md`.

## Secret classes

| Class | Generate with | Rotation |
|---|---|---|
| Signing key (JWT) | `openssl rand -hex 32` | On leak; invalidates all tokens |
| Encryption key at rest | `openssl rand -hex 32` | Only with a re-encrypt migration |
| Service password | `openssl rand -base64 24 \| tr -d '+/=' \| head -c 24` | Yearly or on leak |
| Third-party credential | Provider console | On leak |

`ctl setup` generates a blank key whose name holds a `_PASSWORD`, `_KEY` or `_SECRET` segment, at the end or followed by more (`ENCRYPTION_KEY_PYTHON`). Keep provider-issued credentials commented out until configured; the generator cannot distinguish an active blank provider key from a local generated key. Shared credentials use one key; separate credentials use separate names. Write each secret's recovery procedure beside its template entry when adapting the project, because a rotation needs the service-specific steps. Rotate leaked credentials even after removing them from the working tree, because Git retains history.

## Template rules

- Use the two-line hash headers in `template/.env.template` so settings are easy to find by kind.
- Name each key's reader and generation method in its comment so an operator knows how to fill it.
- Keep secrets blank so the committed template contains no credentials. Give non-secrets development defaults so setup produces usable local settings.
- Compose values from leaves (`DATABASE_URL=postgresql://${POSTGRES_USER}:…`) so changing a host requires one edit.
- Keep optional integrations as commented blocks so setup does not generate provider credentials.
- Ignore `.env` and `.env.*`; allow only the root `!/.env.template`. Exclude env files from Docker build contexts so secrets cannot enter images.

## `ctl check` on env

The mechanical checks live in `08_ctl.md` § `ctl check`. Browser exposure and the quality of template comments still require review; a green conformance check does not prove those properties.
