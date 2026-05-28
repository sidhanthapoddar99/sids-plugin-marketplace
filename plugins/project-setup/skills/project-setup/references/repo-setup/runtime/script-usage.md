# `ctl` + `scripts/` — usage reference

The command surface, the dispatcher skeleton, the `scripts/*.sh` map, the host dev loop, and the three startup-path commands. For the model (why `dev` vs `up`, the thin-wrapper principle, the two custom bodies, why-host) start at `script-overview.md`.

## `ctl up` — profiles, one config, stacked modifiers

```
ctl up                              core only (no-profile services: data layer)
ctl up <profile…>                   --profile <p> …                profiles  ∈ app|edge|obs|…
ctl up <profile…> --config=<name>   + compose.<name>.yaml          config    ∈ prod|… (at most one)
ctl up <profile…> --<modifier>…     + compose.m.<modifier>.yaml    modifiers ∈ expose|traefik|no-ports|…
ctl up --help                       list discovered profiles, configs, modifiers
```

- **Auto-discovered**: profiles by grepping `profiles:` in `compose.yaml`; configs are `compose.<name>.yaml`; modifiers are `compose.m.<name>.yaml`. No hard-coded lists — drop a file and it appears in `--help`.
- **`--config=prod` switches `--env-file` to `.env.production`** when present.
- **Always echoes the composed command** before running, so the active set is never hidden.

```
ctl up app edge --config=prod --traefik
▸ docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml --profile app --profile edge --env-file .env.production up -d
```

The compose-file convention these assemble (profiles vs config vs `.m.` modifier, path discipline) is `docker-overview.md`.

## Command surface

```
ctl dev [target]      run the stack LOCALLY on the host (hot reload). target ∈ all|backend|frontend|<svc>
                      auto-ensures the data core (with ports) is up first. foreground; Ctrl-C/q stops.
ctl up [profile…] [--config=<name>] [--<modifier>…]   start container stack, detached
ctl up --help         list discovered profiles, configs, modifiers
ctl down [service]    stop the project (or named service)
ctl restart [service]
ctl ps                unified view: running containers + running local dev procs
ctl logs [service] [-f]
ctl status [service]  config doctor — project-custom body (scripts/status.sh)
ctl setup             interactive .env / config.local.yaml wizard — project-custom body (scripts/setup.sh)
ctl migrate {up|down|new|status}   alembic (lives here, not under dev)
ctl test [target]
ctl build             production image build
ctl clean             tear down + clear caches (asks first)
ctl help              print the contract
```

`ctl dev backend` (backend on the **host**, reloading) and `ctl up app` (backend **container**) differ by *where it runs* — `dev` = host, `up` = docker. `ctl help` and `ctl status` must spell that out.

## Dispatcher skeleton

The full runnable version is `assets/snippets/scripts/dev-wrapper.sh` (drops in as `ctl`). The load-bearing part is discovery + the `ctl up` assembly — everything else is thin routing:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; cd "$REPO_ROOT"
DOCKER_DIR="docker"; BASE="$DOCKER_DIR/compose.yaml"
DATA_SVCS=(postgres redis)               # the no-profile core ctl dev depends on
c_info(){ printf '\033[36m▸\033[0m %s\n' "$*"; }
die(){    printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# discovery — no hard-coded lists. compose.m.* = modifiers; the rest (minus base) = configs.
list_profiles()  { grep -hoE 'profiles:[[:space:]]*\[[^]]+\]' "$BASE" | grep -oE '[A-Za-z0-9_-]+' | grep -vx profiles | sort -u; }
list_configs()   { for f in "$DOCKER_DIR"/compose.*.yaml; do [[ -e $f ]] || continue; b=${f##*/}; [[ $b == compose.yaml || $b == compose.m.* ]] && continue; b=${b#compose.}; echo "${b%.yaml}"; done; }
list_modifiers() { for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue; b=${f##*/compose.m.}; echo "${b%.yaml}"; done; }

cmd_up() {                               # profiles + one --config + stacked --<modifier>
  local profiles=() config="" modifiers=()
  while [[ $# -gt 0 ]]; do case "$1" in
    --config=*) [[ -z $config ]] || die "one --config at a time"; config="${1#--config=}"; shift ;;
    --*)        modifiers+=("${1#--}"); shift ;;       # --expose → modifier 'expose'
    -*)         die "unknown flag: $1" ;;
    *)          profiles+=("$1"); shift ;;
  esac; done
  local files=("$BASE") prof_args=() env_args=()
  if [[ -n $config ]]; then
    local cf="$DOCKER_DIR/compose.$config.yaml"; [[ -f $cf ]] || die "no such config '$config'"
    files+=("$cf"); [[ $config == prod && -f .env.production ]] && env_args=(--env-file .env.production)
  fi
  local m; for m in "${modifiers[@]}"; do                # modifiers stack last (they win)
    local mf="$DOCKER_DIR/compose.m.$m.yaml"; [[ -f $mf ]] || die "no such modifier '$m'"; files+=("$mf")
  done
  local p; for p in "${profiles[@]}"; do
    list_profiles | grep -qx "$p" || die "no such profile '$p'"; prof_args+=(--profile "$p")
  done
  local cmd=(docker compose) f; for f in "${files[@]}"; do cmd+=(-f "$f"); done
  cmd+=("${prof_args[@]}" "${env_args[@]}" up -d)
  c_info "${cmd[*]}"; "${cmd[@]}"                         # echo composed cmd, then run
}

# dev → ensure data core + process-compose/dev-host;  down/ps/logs → thin compose wrappers;
# setup|status|migrate|test|build|clean → exec scripts/<cmd>.sh  (see the script map below)
```

Discovery is a one-line `grep`/glob — convention over a YAML parser, deliberately. (Assumes the inline `profiles: [app]` form.)

## Worker scripts — two worked bodies

`ctl` routes each real-body command to a self-contained `scripts/<name>.sh` (`set -euo pipefail`, exits non-zero, one job). The full list, roles, and folder layout are the **script map in `script-overview.md`**; the runnable set ships in `assets/snippets/scripts/`. Two representative bodies:

### Example — `scripts/wait-for-health.sh`

```bash
#!/usr/bin/env bash
# Wait for given compose services to report healthy.
# Usage: ./scripts/wait-for-health.sh postgres redis [timeout-seconds]
set -euo pipefail
services=("$@"); timeout=60
if [[ "${services[-1]}" =~ ^[0-9]+$ ]]; then timeout="${services[-1]}"; unset 'services[-1]'; fi
proj="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"; elapsed=0
while (( elapsed < timeout )); do
  all_healthy=true
  for svc in "${services[@]}"; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "${proj}-${svc}" 2>/dev/null || echo "unknown")
    [[ "$status" != "healthy" ]] && { all_healthy=false; break; }
  done
  $all_healthy && { echo "✓ all healthy: ${services[*]}"; exit 0; }
  sleep 2; elapsed=$((elapsed + 2))
done
echo "✗ not healthy within ${timeout}s: ${services[*]}" >&2; exit 1
```

### Example — `scripts/check-env.sh`

```bash
#!/usr/bin/env bash
# Diff .env keys against .env.example. Fail on missing keys.
set -euo pipefail
[[ -f .env && -f .env.example ]] || { echo "✗ need both .env and .env.example"; exit 1; }
declare -A actual
while IFS='=' read -r k _; do [[ -z "$k" || "$k" =~ ^# ]] || actual["$k"]=1; done < .env
missing=()
while IFS='=' read -r k _; do [[ -z "$k" || "$k" =~ ^# ]] && continue; [[ -v actual[$k] ]] || missing+=("$k"); done < .env.example
(( ${#missing[@]} )) && { echo "✗ missing in .env: ${missing[*]}"; exit 1; }
echo "✓ .env matches .env.example schema"
```

## `ctl setup` + `ctl status` — the two custom bodies

**`scripts/setup.sh`** (the wizard): copy `.env.example` → `.env` if missing (never overwrite); walk the **REQUIRED** keys and prompt each, showing the current value; generate secrets the user shouldn't invent (`openssl rand -hex 32`); optionally seed `config.local.yaml`; ensure bind-mount data dirs exist (`mkdir -p data/postgres/pgdata data/redis/data`); end by printing `ctl status`. Keep it idempotent — re-running tops up, never clobbers.

**`scripts/status.sh`** (the doctor) is read-only; checks (project-specific, consistent shape):

| Check | Example |
|---|---|
| `.env` exists, matches `.env.example` schema | no missing keys, no empty REQUIRED |
| `config.local.yaml` present (dev) | warn if absent — defaults won't apply |
| Per-service config | backend `config.yaml` valid; frontend `.env` has `VITE_*`/`NEXT_PUBLIC_*` |
| Dependencies reachable | data containers up? ports free? `mise` tools installed? |
| Secrets not placeholder | REQUIRED keys aren't still `changeme` |

```
$ ctl status
✓ .env present, matches .env.example
! config.local.yaml not set — using config.yaml defaults
✓ backend: config.yaml valid, DATABASE_URL set
✗ frontend: VITE_API_BASE_URL empty — set it in apps/web/.env
✓ infra: postgres + redis healthy
```

Report per area (backend / frontend / infra), green/yellow/red, with the fix for each red. `ctl status` calls `check-env.sh` (the env-schema diff) and layers per-service + reachability checks on top.

## `ctl dev` — the host loop

`ctl dev` (1) brings up its data-container deps (`postgres`, `redis`, with ports) via `docker compose` and waits for healthchecks (`scripts/wait-for-health.sh`); (2) starts each app as a host process with hot reload; (3) multiplexes output into per-service panes; (4) stops everything cleanly on Ctrl-C. Steps 2–4 are delegated to a process runner — don't hand-roll PID juggling.

### Preferred: `process-compose.yaml`

```yaml
processes:
  backend:
    command: "uv run uvicorn app.main:app --reload --port ${PYTHON_PORT:-8000}"
    working_dir: "apps/backend"
    readiness_probe: { http_get: { host: localhost, port: 8000, path: /health } }
  frontend:
    command: "bun dev"
    working_dir: "apps/frontend"
    depends_on: { backend: { condition: process_healthy } }
```

`ctl dev` runs all; `ctl dev backend` runs one. `depends_on` orders the host processes; the data-container auto-up orders the containers before them — declare deps, let the runner honour them. If a declared dep can't start, fail loudly with the fix, never start half a stack.

### Fallback: bash `trap` (`scripts/dev-host.sh`, ≤ 2 processes)

```bash
prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }
( cd apps/backend  && uv run uvicorn app.main:app --reload --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
```

**Stays in containers** (via `ctl up`): postgres + any stateful service, redis, Seaweed/Meilisearch/Neo4j, optionally an nginx for routing tests. **Runs on host** (via `ctl dev`): Python/Rust backends with `--reload`/`cargo-watch`, the frontend dev server, test runners.

**Reverse proxy in dev:** default is the **Vite proxy** (`vite.config.ts` proxies `/api/*` to the backend host port — CORS-free, no extra container); or `ctl up edge` for a local nginx if you need prod-like routing. In prod (`ctl up app edge --config=prod`), nginx/traefik routes the same `/api/*` over the compose network — only the proxy changes.

**When host-mode doesn't fit a service:** heavy native deps (exotic glibc, GPU libs) → containerise *that one service* (give it a profile), keep the rest on host. Cross-platform team that can't install the toolchain → offer `ctl up app` as the containerised path, but keep host as the `ctl dev` default.

## Three startup paths — the commands

Every README documents all three (concept in `script-overview.md`). The exact commands:

````markdown
## Get started

```bash
git clone <url> && cd <repo>
mise install        # also puts `ctl` on PATH inside the repo
ctl setup           # interactive: fills .env, generates secrets
ctl dev             # apps on host (hot reload), data core in containers
```

### Other ways to start

```bash
# raw docker compose — what ctl does under the hood
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d                     # data core, ports published
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml --profile app up -d       # + app services
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml \
    --profile app --profile edge --env-file .env.production up -d                                # production

# no docker — host run (IDE debugger attach, profiling, one service in isolation)
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d   # data core only
cd apps/backend && uv sync && uv run alembic upgrade head && uv run uvicorn app.main:app --reload --port 8000
cd apps/frontend && bun install && bun dev                                    # new terminal
```
````

The no-docker path is what `ctl dev` automates; documenting it raw lets a developer attach a debugger to one service. **Prod** is `ctl up app edge --config=prod` — keep development (`ctl dev`) distinct from deployment in the README's Deploy section.

`/ps-setup audit` checks the README shows all three paths. Drift to flag: only `ctl dev` (can't debug compose), only `docker compose` (no fast-iteration story), only raw host run (everyone reinvents the flow).

## Anti-patterns

- Logic inside `ctl` that belongs in a script — split when a subcommand grows past ~30 lines.
- Hardcoding service names that should come from compose project naming.
- Forgetting `set -euo pipefail` in a worker — silent failures bite.
- A `status` that just greps for files — it should check reachability and REQUIRED-value-ness, not mere presence.
- Generating prod secrets via the interactive wizard — prod injects real env vars.
- "Just run `make dev`" with no explanation, or a Getting-Started wiki separate from the README — keep the contract in the repo.
- Different commands in CI vs README — CI uses the same documented commands (or a superset).

## See also

- `script-overview.md` — the model (dev vs up, thin wrapper, the two custom bodies, why-host, three-paths concept)
- `docker-overview.md` — profiles / config / `.m.` modifiers; `docker/` layout + path discipline
- `mise.md` — project-scoped PATH; `ctl` callable bare
- `assets/snippets/scripts/dev-wrapper.sh` (+ `scripts/*.sh`) — the runnable dispatcher and workers
- `references/architecture/frontend/vite-proxy-nginx-pair.md` — dev proxy → prod nginx
