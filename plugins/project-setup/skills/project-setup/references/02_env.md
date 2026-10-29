# Env — root `.env`, `config.yaml`, `config.local.yaml`

Configuration has one root environment file and per-backend settings. Template: `template/.env.template`, `template/apps/example-api-python/config.yaml`.

| File | Where | Holds | Read by | Committed |
|---|---|---|---|---|
| `.env` | root | Debugging, authentication, service addresses, data paths, secrets, testing, deployment and worktree settings, grouped by kind | `ctl`, Compose interpolation, backend loaders | no; `.env.template` yes |
| `config.yaml` | each backend | All settings of that backend. `${VAR}` for secrets and endpoints. Literals for defaults. | backend loader | yes |
| `config.local.yaml` | each backend | Developer overrides of literals. Never a secret. | backend loader | no |

## Rules

1. **One environment contract.** Keep every environment key in the root `.env.template`, with blank secrets and useful non-secret defaults, so an operator can find the whole contract in one place. Group keys by kind with two-line hash comment headers, as shown in the template: debugging, authentication, service addresses, data paths, secrets, rust, testing, deployment and worktrees. Within each section, use single-hash service subheadings such as `# Postgres` and `# Redis`, with one blank line between groups. Keep addresses and prefixes in the service-address section and credentials in the secrets section. Put comments above variables rather than on assignment lines so values are easy to scan and edit. Each setting belongs in one group. Four sections belong to one page each:
    - authentication holds `AUTH_ENABLED`, the backends' sign-in switch, and `14_development-sign-in.md` owns its rules;
    - rust holds `CTL_RUST_DEBUG`, which `ctl` hands to Cargo, and `10d_test-speed-and-resources.md` owns it;
    - testing holds `TEST_CPUS`, `TEST_BUILD_JOBS` and `TEST_MEMORY`, which `ctl gate` and `ctl test` read, and `10d_test-speed-and-resources.md` owns them;
    - worktrees holds `WORKTREE_SLOTS`, `WORKTREE_TRIM_DAYS` and `WORKTREE_ONLY`, and `13_worktree.md` owns them.
2. **Process inheritance is different from browser exposure.** `ctl` exports the loaded environment to child processes, including frontend dev servers. A dev server can therefore read secrets in its server process. Expose only explicitly selected public constants to browser code. Never serialize or spread `process.env`, use an empty env prefix, or put secrets in `VITE_*`, `NEXT_PUBLIC_*` or `PUBLIC_*` variables that the framework exposes. A root file is not a security boundary between local processes.
3. **Service addresses define both binding and routing.** Use `<PIECE>_HOST`, `_PORT`, `_PREFIX` for each proxied piece; backends may add `_URL`. Static frontends need `_PORT` and `_PREFIX` only. The piece owning `/` has no `_PREFIX`. The service and proxy read the same keys so their routes agree. Missing required values fail instead of using literal fallbacks. Under Docker, Compose decides internal service names and ports (`api:8000`); root `.env` ports control host exposure.
4. **Keep credentials out of browser constants and build args.** Addresses in `.env` are not automatically public, and a URL may contain a password. Browser code calls the same-origin backend route for operations requiring credentials. Only a Next.js server's server-side code may use server credentials.
5. **Load one root file.** `ctl` passes `--env-file <root>/.env` to Compose explicitly. Do not add app env files or depend on Compose discovering one from the current directory, because commands must behave the same from every working directory. Docker services receive declared `environment:` keys, never the whole file via service `env_file:`.
6. **Resolve values before launching consumers.** Every storage path derives from `BASE_DIR`. § Host storage paths gives the path rules. `ctl` anchors Compose with `--project-directory <root>`, so a relative path means the same to both. Values may reference other keys with `${KEY}`: `BACKUP_DIR=${LOGS_DIR}/backups`. The loader first loads all keys skip-if-set, then resolves references using the winning environment values. It uses text substitution, never `eval`. An unset reference or a cycle fails naming the key. The loader also resolves a reference to a later line, but Compose reading the file without `ctl` leaves that reference blank, so declare each key above the keys that read it. Template: `template/scripts/common/_lib.sh`, `expand_env_refs`.
7. **Preserve backend precedence.** Process environment > `config.local.yaml` > `config.yaml`. Load the root file skip-if-set so inline overrides and CI-injected secrets win, including an explicitly empty value. The nested override `<APP>__<SECTION>__<KEY>` (`API__DATABASE__POOL_SIZE`) overrides literals; `${VAR}` names environment values used in YAML.
8. **Keep defaults in one place.** Do not add `config.<env>.yaml` layers or default forms such as `${VAR:-8000}` in backend settings. An unset reference fails; a literal default belongs in `config.yaml`. Prefix separate databases (`AUTH_DATABASE_URL`, `BILLING_DATABASE_URL`) and nested overrides (`API__`, `ENGINE__`) so services sharing a host do not collide.
9. **Audit the template.** Read `.env.template`, never a filled `.env`, because audit output is a log and the filled file holds live secrets. `ctl setup env` writes `.env` from the template, as § Merging `.env` with its template describes. `ctl status` compares key names with the template.
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

Declare locally generated credentials in `scripts/config/generated-credentials.conf`. Each line names a key and its generator, so an arbitrary token name can be generated without treating provider API keys as local secrets. `hex32` generates 32 random bytes as hexadecimal; `password24` generates a 24-character password. The shipped file contains only credentials used by the example services. A project adds its own token to both `.env.template` and this declaration file when a service actually needs it. Remove declarations when removing their services.

```text
POSTGRES_PASSWORD password24
JWT_SIGNING_KEY hex32
```

Leave provider-issued credentials out of this list, including names ending in `_TOKEN`, `_KEY` or `_SECRET`: those suffixes do not authorize generation. Optional integrations may stay commented out in the template. The env step (§ Setting up `.env`) preserves supplied file values and process overrides, and a rerun does not rotate a generated credential. It reports key names, never generated values. Template: `template/scripts/config/_credentials.sh`.

List required supplied credentials in `scripts/config/required-credentials.conf`, one name per line, and declare them in `.env.template`. The env step requires their effective values but never generates them. Active generated credentials are already required. An explicitly empty process override remains empty and fails that requirement. Commented or absent template keys are inactive; other blank settings produce a named warning and remain subject to the application's validation. A key that is blank by design gets no warning: write what an empty value means on the comment line right above it, as `# empty: every core` or `# … Empty: 4`, because the env step reads that line. This keeps optional integrations optional without claiming that an unconfigured required provider is ready.

Shared credentials use one key; separate credentials use separate names. Write each secret's recovery procedure beside its template entry when adapting the project, because a rotation needs service-specific steps. Rotate leaked credentials even after removing them from the working tree, because Git retains history.

## Setting up `.env`

The env step writes `.env`, its credentials and the storage folders it names. `ctl setup env` runs the env step and stops. `ctl setup` runs the same step first, then installs the toolchains and dependencies (`08_ctl.md` § Setup and tool availability). One function, `setup_env` in `template/scripts/config/setup.sh`, is the env step, so the two commands cannot drift. The step does three things in order:

1. It creates `.env` from `.env.template` when `.env` is missing, with mode `600`. Otherwise it rebuilds `.env` in the template's shape and keeps every value, as § Merging `.env` with its template describes.
2. It generates the blank declared credentials and requires the active ones, as § Secret classes describes.
3. It resolves the storage paths, as § Host storage paths describes. Then it creates `DATA_DIR/<service>` for each data-core service that `DATA_SVCS` in `template/scripts/common/_lib.sh` lists, `LOGS_DIR/dev`, `LOGS_DIR/run`, `LOGS_DIR/test_build` and `BACKUP_DIR`.

The step installs nothing, so it runs before the versions are resolved, and on a server, which builds its images in Docker and needs no host toolchain. A rerun adds only what is missing: keys the template gained, blank declared credentials and storage folders. It changes or removes no value without a yes, so a rerun is safe on any checkout. The storage folders belong to this step because `.env` names them and creating them installs nothing. Docker would otherwise create a missing bind-mount source owned by root.

## Merging `.env` with its template

`sync_env_template` in `template/scripts/config/_env-merge.sh` merges each file of `ENV_FILES` with its template. The result has the template's sections, comments, blank lines and key order, so a key the template gains lands in its section, under its comment. Each value `.env` holds is kept byte for byte, because the step copies the whole line: quotes, an `=` inside the value, a trailing comment and an empty value included. A key line is a line that starts, at column 0, with a name and `=`, the same lines the loader reads.

| `.env` holds | The merged file holds |
|---|---|
| a key the template declares | the `.env` line, where the template has the key |
| no line for a key the template declares | the template's line, named under "added from the template" |
| a key the template shows commented out, such as `# BETA_API_PORT=` | the `.env` line, in place of the commented line |
| a key the template lacks | the `.env` line, in a last section headed `# Not in .env.template (kept by ctl setup)`, until you agree to remove it (below) |
| a template comment, current or from the last run's template | the template's current text, so a reworded comment shows its new wording once |
| a comment line the template never had, a local comment | that line, kept with its key by the rules below |
| a blank line | nothing. Blank lines come from the template |
| the same key twice | nothing changes. The step stops and names the key and both lines, because which value wins would be a guess |

**Local comments.** A comment line in `.env` is local when neither the template nor `.env.template.synced` holds it. Any other line that is neither blank nor a key line, such as an indented line, counts as a comment line, so no line is lost. `.env.template.synced` is a copy of the template from the last run, which the step writes beside `.env` after every run. It exists because a template comment that was reworded or deleted would otherwise look like a comment a person wrote, and it would stay in `.env` for ever. A local comment goes to the first place that fits:

1. A key line below it, with no blank line between: directly above that key, below the key's template comment.
2. No key line above it in `.env`: at the top of the file. A note above the file's header stays there.
3. Otherwise: at the end of the paragraph that holds the nearest key line above it. A note at the end of a section stays at the end of that section.

Each rule puts a comment where the same rule finds it on the next run, so a second run changes nothing. A local comment goes with its key, into the last section too, and it is removed with its key. The rules keep a comment next to its key, not its exact line: a comment written above a key's template comment moves below it on the first run, and the blank lines inside a block of local comments go.

A checkout from before this rule has no `.env.template.synced`. Its first run keeps every comment line the template lacks, old template text included, and says so, because a dropped comment cannot come back. Delete the stale lines once; from then on the record tells the two kinds apart.

**Keys the template lacks.** The step never removes a value without a yes, because a dropped secret is lost. When `.env` has keys the template lacks, a terminal sees one list of key names and one question for the whole list:

```text
These keys are in .env but not in .env.template:
  OLD_FEATURE_FLAG
  LEGACY_S3_BUCKET
? Remove them from .env? [y/N]
```

Anything but `y` or `yes` keeps them in the last section, and the step names them. With no terminal, as in CI or a pipe, the step never asks and never removes; it keeps the keys and names them. `ctl setup --remove-unlisted` or `ctl setup env --remove-unlisted` removes them without asking, for a script. To keep one key and remove the others, answer no and delete the others by hand, or add the key to the template. The output names keys only, never a value or a comment, because `.env` holds secrets and a screen or a log may be read by someone else.

**The write.** The step writes only when the merged file differs from `.env`. It writes a temporary file beside `.env`, mode `600`, keeps the previous file as `.env.bak`, mode `600`, and then renames the temporary file over `.env`. So a failure at any point leaves `.env` whole, and `.env.bak` undoes a merge or a removal. `.env.bak` and `.env.template.synced` are ignored by the `.env.*` lines of `.gitignore` and `.dockerignore`. When `.env` is a symbolic link and must change, the step stops and changes nothing, because the rename would replace the link with a file. The output then lists the keys added, the number of local comment lines kept, and the keys kept or removed.

## Host storage paths

Every storage path hangs off one root, `BASE_DIR`, so one setting moves them all. This is the DATA PATHS section of `template/.env.template`:

```dotenv
# Storage
# Local paths are relative to this repository, or absolute deployment paths.
# In production it can be /DATA/AppData/<Company-Name>/<Project-name>.
BASE_DIR=.

DATA_DIR=${BASE_DIR}/data

# Logs and backups
LOGS_DIR=${BASE_DIR}/logs
BACKUP_DIR=${LOGS_DIR}/backups
```

`DATA_DIR` holds actual data: the engine bind mounts (`${DATA_DIR}/postgres` …), datasets and uploads. `LOGS_DIR` holds produced state: dev logs in `dev/`, process records in `run/`, deploy transcripts in `deploy/` and frozen builds in `test_build/`. `ctl db backup` writes `BACKUP_DIR/<timestamp>/`.

Set the root by these rules:

- Keep `BASE_DIR=.` in a checkout. Each checkout, a git worktree included, then keeps its own `data/` and `logs/`, and their own ignore files cover them.
- If a checkout needs another relative value, start it with `./`, because Compose reading the file without `ctl` takes a bare `state/data` for a named volume. Add the folder it names to `.gitignore`, because no shipped ignore file covers it.
- On a deployment host, write an absolute `BASE_DIR` in `.env`, such as `/DATA/AppData/<Company-Name>/<Project-name>`. Write it in the file, not only in the shell, because every later `ctl` run and every Compose call read the file.
- Leave the derived lines as they are, so `BASE_DIR` keeps moving all of them. To place one path elsewhere on purpose, such as data on a fast disk, write an absolute path. A relative path stays at the repo root when `BASE_DIR` moves, and `ctl check` fails on it (`08_ctl.md` § `ctl check`).
- A changed `BASE_DIR` moves no existing file. Run `ctl stop`, move the folders to the new path, then start again, because the engines start empty at a path that holds no data.

`ctl` loads `.env` skip-if-set, then `expand_env_refs` replaces each `${NAME}` (rule 6). A value set in the shell wins, and every path that derives from it follows: `BASE_DIR=/srv/app ctl up` moves the three derived paths with it. Compose resolves `${BASE_DIR}` inside the `--env-file` the same way, with the shell value first, so `ctl` and Compose without `ctl` mount the same path.

`resolve_storage_dirs` in `template/scripts/common/_paths.sh` then exports `BASE_DIR`, `DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` as absolute paths. It anchors a relative value at `CTL_ROOT`, not at the shell's current directory or the `docker/` directory, because Compose anchors it at the same `--project-directory`. It keeps an absolute value. It removes `.` segments and doubled or trailing slashes, and it keeps spaces. A second call changes nothing. An unset key takes its template default. It fails naming the key on a blank value, an unexpanded `${NAME}`, or a `..` segment, because each would select a directory nobody configured.

Setup, host launch, process lookup, frozen builds, backups and Compose execution call this helper before they use a storage path. Container startup validates the paths before rendering its model: a bare relative directory becomes an absolute bind-mount source, and an empty directory cannot become an unintended filesystem-root mount. Do not resolve every key ending in `_DIR`, because application-specific paths and container destinations belong to their consuming code. Compose still receives its explicit root project directory, including the root override on included files. Backend-specific storage initialization remains project-owned.

## Template rules

- Use the two-line hash headers in `template/.env.template` so settings are easy to find by kind.
- Name each key's reader and generation method in its comment so an operator knows how to fill it.
- Keep secrets blank so the committed template contains no credentials. Give non-secrets development defaults so setup produces usable local settings.
- Compose values from leaves (`DATABASE_URL=postgresql://${POSTGRES_USER}:…`) so changing a host requires one edit.
- Keep optional integrations as commented blocks so unused integrations do not require configuration. Provider credentials never appear in the generation list.
- Ignore `.env` and `.env.*`; allow only the root `!/.env.template`. Exclude env files from Docker build contexts so secrets cannot enter images.

## `ctl check` on env

The mechanical checks live in `08_ctl.md` § `ctl check`. Browser exposure and the quality of template comments still require review; a green conformance check does not prove those properties.
