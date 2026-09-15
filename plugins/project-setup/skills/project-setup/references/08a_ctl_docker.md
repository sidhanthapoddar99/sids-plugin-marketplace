# ctl up — the compose model

`ctl up` assembles a stack from files under `docker/` and runs it. There are five things you touch. Each has one file rule and one `ctl up` flag. This page is their home; `08_ctl.md` holds the verb table and points here. Template: `template/docker/`, `template/scripts/container/up.sh`.

## The five things you touch

| # | Thing | File rule | `ctl up` flag | Chosen how |
|---|---|---|---|---|
| 1 | Config | `docker/compose.<name>.yaml` | `--config <name>` | single pick; `base` is the default |
| 2 | Modifier | `docker/compose.m.<name>.yaml` | `+<name>` | multi pick, only the ones that fit the config |
| 3 | Service subset | a service the assembled files define | `--services a,b` | multi pick, all preselected |
| 4 | Preset | one line in `docker/presets.yaml` | `ctl up preset <name>` | single pick, or by name |
| 5 | Include | `include:` inside a config | none | a config borrows another file |

### 1. Config — one stack shape

A config is a compose file that stands on its own. `ctl up --config <name>` runs it. The name is the middle of the filename, and a name holds no dot, so `compose.m.*` is never a config. Discovery is by filename; there is no list to maintain.

| Config | What it is | Run by |
|---|---|---|
| `base` | The whole stack. This is prod. The default of `ctl up`. | `ctl up` |
| `db` | The data engines and the schema one-shots. | `ctl dev`, through the reserved preset `dev` (`--config db +expose_db`) |
| `dev` | The dev proxy: one nginx on the host network. | `ctl dev --proxy` |

Rules a config obeys, and `ctl check` proves:

- **A config publishes no port.** Compose lists only union across files, so exposure can only be added, by a modifier. This is what makes `base` safe to run on a server as it is.
- **Every path is root-relative.** `ctl` runs compose with `--project-directory <root>`, so every path is `./apps/…` or `./data`. Never `../`.
- **No `env_file`.** Each service lists exactly the variables it reads under `environment:`. `${VAR}` when the operator decides, a literal when compose decides.
- **Every config validates alone.** `docker compose config` on the file must pass.

To add a config, add `docker/compose.<name>.yaml`. Examples: a worker stack, an admin-only stack, a stack for one customer. The picker shows it on the next run. When one config exists, the picker is skipped.

### 2. Modifier — an overlay

A modifier is a partial compose file laid over a config. It adds ports, re-points an upstream, hands a service one more variable. Given as `+name` tokens, or as `--modifier a,b`. You can give several. They apply in the order given. Merge order is the config first, then each modifier: maps merge per key, scalars replace whole, lists union.

| Modifier | Adds | Fits |
|---|---|---|
| `+expose_web` | `web` on the `_PORT` of the piece that owns `/` | `base`. The default for local docker. |
| `+public` | `web` on `${HTTP_PORT}` / `${HTTPS_PORT}`; `PUBLIC_URL` to the apps | `base`. A public deployment. Refused while one of the three keys is blank. |
| `+expose` | Every app port to the host, each on its own `_PORT` | `base`. Debug. Never prod. |
| `+expose_db` | Each engine on loopback, on its `_PORT` from `.env` | `base`, `db`. What `ctl dev` needs so host processes reach the engines. |
| `+env_override` | Re-points upstreams and URLs to `${VAR}` from `.env` | `base`. A piece runs outside this compose. |

**Which modifiers fit a config is computed, never declared.** `ctl up` runs `docker compose config` on the config plus the modifier. Pass means it fits and it is offered. A modifier can patch a service the config does not define. Then the merged service has no image and compose rejects it. `ctl up` hides that modifier. There is no compatibility list in any file to keep in sync. A modifier whose `MODIFIER_REQUIRES` keys are blank cannot be tested, so it is listed on every config and refused by name when picked.

`DEFAULT_MODIFIERS` in `_lib.sh` names what applies on `base` when nothing is given. Any other config defaults to none, so `--config db --nqa` gets none. On `base`, a default that compose rejects is an error with compose's message, never a silent drop, because a stack that came up without its expected port would look right.

### 3. Service subset — build and run only these

`--services a,b` names a subset of what the assembled files define. Compose builds and starts only the named services and their `depends_on` chain. Nothing else is built, nothing else is started. So:

- `--services api` brings `postgres`, `redis`, `migrate` and runs the schema step, because `api` waits on it.
- `--services postgres` brings `postgres` and nothing else. No schema step, because nothing waits on it.

The plan still lists every service in the file set and marks the subset, so the reader sees what the files hold and what will run.

### 4. Preset — a saved line

`docker/presets.yaml` holds one line per preset:

```yaml
dev: "--config db +expose_db"
local: "--config base +expose_web"
public: "--config base +public"
```

The value is exactly what follows `ctl up` on the command line. It is the reproduce line the plan prints. So `ctl up preset local` is `ctl up --config base +expose_web` with every picker skipped: it goes straight to the plan and the confirm, and `-y` skips the confirm too. There is no second parser and no schema; a text editor writes a preset as well as `set-preset` does.

| Verb | Does |
|---|---|
| `ctl up preset <name> [-y]` | run the stored line; plan, confirm, start. No `--config`, `+modifier` or `--services` beside it: a preset is the whole shape. |
| `ctl up preset` | pick one in a terminal, then the same |
| `ctl up preset --list` | the stored presets and their lines. Needs no docker. |
| `ctl up set-preset [<name>]` | walk the pickers, then Save, Save and run, Back or Cancel. An existing preset's values are preselected, so editing one is re-walking it. Flags given skip their prompt, so `set-preset x --config db +expose_db -y` needs no terminal. Docker must be up, because the plan is the real merge. |

A preset stores the stack shape only: `--config`, `+modifier`, `--services`. Give run flags (`-y`, `-a`, `--nqa`) on the command line. `ctl up preset` refuses a preset that stores one and names the flag. A flag in the file would act on every reader. A line without `--config` means `base`. An empty line is an error. A name is letters, digits, `-` and `_`. A duplicated name: the first line wins on read, and `set-preset` collapses it to one line.

The file is committed. It holds names, never values. One name is reserved: `dev` is what `ctl dev` starts for its data core, so editing that line changes what the dev loop brings up. When it is missing, `ctl dev` stops and says which line to add. It never falls back to a hidden default.

### 5. Include — one file, borrowed

`include:` lets one config pull another whole file in. `base` includes `db`, so the engines and the schema one-shots are defined once and `base` gets them without a copy. A future config that needs the engines includes the db file the same way.

```yaml
include:
  - path: ./docker/compose.db.yaml
    project_directory: .
```

`project_directory: .` is required. Without it the included file's relative paths resolve against `docker/`, so `${DATA_DIR}/postgres` lands in `docker/data/`. Never define the same service in both files. The compose specification calls that a conflict; compose 5.5 let the including file win without a word in a test. Neither outcome is what you want. Include is for borrowing; a deliberate change is a modifier, where the plan shows it.

## How they combine

```
config  ──►  + modifier  ──►  + modifier  ──►  subset  ──►  plan  ──►  confirm  ──►  up
base         expose_web                       api,web      compose      Run / Back     -d --build
                                                           config       / Cancel
```

The plan is the real `docker compose config` merge. It validates the combination before anything starts, prints one row per service with ports, network and volumes, and prints the exact `--nqa` line that reproduces the run. An invalid combination fails there, with compose's own message, and nothing has started.

Bare `ctl up` in a terminal walks config, modifiers, services, plan, confirm. Anything given on the command line skips its prompt. No terminal and nothing given is the default: `base`, `+expose_web`, every service, and the run refuses without `-y`. `--nqa -y` is the scripted form.

## Worked example — the database

The engines live in the `db` config with no ports. Two one-shot services live beside them:

| Service | Runs | Image |
|---|---|---|
| `migrate` | `alembic upgrade head` in `apps/database/postgres/`, bind-mounted at `/work` so `new` writes back | built from `apps/database/postgres/Dockerfile` |
| `neo4j-init` | `cypher-shell -f init.cypher` | the neo4j image, which ships the shell |

Both run inside the compose network, so no engine port is published for them. Both are idempotent and exit 0 when applied. Every backend waits on them with `condition: service_completed_successfully`; the edge and the server frontend wait on a backend, so they wait too. Compose orders engines, schema, apps by itself. An app never migrates on its own boot. It waits.

| Situation | What runs | Ports |
|---|---|---|
| `ctl dev` | `ctl up preset dev --nqa -y` (the reserved preset: `--config db +expose_db`), then `docker compose wait` on the one-shots (nothing in that config depends on them), then the apps on the host | engines on loopback, so host processes reach them |
| `ctl up` | `base`: engines, one-shots, apps | none on the engines; the edge through a modifier |
| `ctl up --services api` | `postgres`, `redis`, `migrate`, `api` | as above |
| `ctl db migrate` | `docker compose run --rm --no-deps --build migrate alembic upgrade head`, then `neo4j-init` when `neo4j` is in `DATA_SVCS` and `init.cypher` exists. Both against the `base` file, which includes the db file, so the same containers are found. | none; the engines must already be up |
| `ctl db migrate new "<msg>"` | the same container, `alembic revision`, run as your user so the files are yours | none |
| `ctl manage` | inside the running `api` container under `ctl up`; on the host under `ctl dev` | none published for the container path |

`--no-deps` on `ctl db migrate` matters. `ctl dev` creates the engine containers from `db` plus `+expose_db`. `ctl up` creates them from `base` with no ports. Compose keys a container by service name and recreates it when its spec differs. A switch between `ctl dev` and `ctl up` recreates the engines once. That is acceptable. A `run` that starts its dependencies would recreate them under a live stack. That is not. `ctl db migrate` therefore requires the engines up and never starts them.

Without a data core: `DATA_SVCS=()` and `SCHEMA_SVCS=()` in `_lib.sh`; drop the include and every `depends_on` on an engine or a one-shot from `base`; delete the `db` config, the `dev` preset and `scripts/db/`. `ctl dev` skips the data core when `DATA_SVCS` is empty. `ctl check` then names any `depends_on` left behind, because `base` no longer validates.

## The passthroughs

`down`, `restart`, `logs`, `exec`, `shell`, `health` run against the `base` file. They act on the services that file defines. A service another config defines and `base` lacks is not reachable through them: `ctl down` leaves the `dev` proxy running today, and `ctl dev` stops it itself on Ctrl-C. Known limit, recorded here, not fixed.

One more limit of the port rule: `ctl check` looks for `ports:` in a config. `network_mode: host`, which the `dev` config uses for the proxy, is exposure the check does not see. It exists for that one service, in dev, and nowhere else.

## What ctl check proves

- No config publishes a port. Only a modifier does.
- No `../` in any compose file.
- Every `${NAME}` in the root .env file names a set key, with no cycle.
- Every config validates alone.
- Every modifier fits at least one config, and the fit list is printed, because that list is what `ctl up` offers. A modifier whose required keys are blank is skipped and named.
