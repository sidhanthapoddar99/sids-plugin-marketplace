# Subscripts in `scripts/`

`./dev` is the dispatcher. `scripts/<name>.sh` are the workers. Keeps the wrapper tight and gives each operation its own file.

## Folder

```
scripts/
├── migrate.sh
├── test.sh
├── build.sh
├── wait-for-health.sh
├── check-env.sh
├── db-init.sh
├── seed.sh
└── README.md           # optional — what each script does
```

Every script is executable, takes `set -euo pipefail`, and exits non-zero on failure.

## Naming

- Verb-noun, kebab-case: `db-init.sh`, `wait-for-health.sh`
- `.sh` extension on scripts (so editors syntax-highlight); no extension on `./dev` (it's the public API)
- Each script does **one** thing well

## Example — `scripts/wait-for-health.sh`

```bash
#!/usr/bin/env bash
# Wait for given compose services to report healthy.
# Usage: ./scripts/wait-for-health.sh postgres redis [timeout-seconds]

set -euo pipefail

services=("$@")
timeout=60

# If last arg looks like a number, treat as timeout
if [[ "${services[-1]}" =~ ^[0-9]+$ ]]; then
  timeout="${services[-1]}"
  unset 'services[-1]'
fi

elapsed=0
while (( elapsed < timeout )); do
  all_healthy=true
  for svc in "${services[@]}"; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}-${svc}" 2>/dev/null || echo "unknown")
    if [[ "$status" != "healthy" ]]; then
      all_healthy=false
      break
    fi
  done
  $all_healthy && { echo "✓ all healthy: ${services[*]}"; exit 0; }
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "✗ services did not become healthy within ${timeout}s: ${services[*]}" >&2
echo "  Try: docker compose logs ${services[*]}" >&2
exit 1
```

## Example — `scripts/check-env.sh`

```bash
#!/usr/bin/env bash
# Diff .env keys against .env.example. Fail if missing keys or empty REQUIRED keys.

set -euo pipefail

[[ -f .env ]]         || { echo "✗ no .env"; exit 1; }
[[ -f .env.example ]] || { echo "✗ no .env.example"; exit 1; }

declare -A actual
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  actual["$key"]="$val"
done < .env

missing=()
empty=()
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  if [[ ! -v actual[$key] ]]; then
    missing+=("$key")
  elif [[ -z "${actual[$key]}" && "$val" == "" ]]; then
    # check if .env.example marks it REQUIRED — read with line preceding
    :
  fi
done < .env.example

(( ${#missing[@]} > 0 )) && { echo "✗ missing keys in .env: ${missing[*]}"; exit 1; }
echo "✓ .env matches .env.example schema"
```

(Production-grade `check-env` should also detect REQUIRED markers and empty values — simplified here.)

## Per-language helpers

```
scripts/
├── py/
│   ├── format.sh        # ruff + black
│   └── lint.sh
├── rs/
│   ├── sqlx-prepare.sh
│   └── clippy.sh
└── fe/
    └── biome.sh
```

Optional nested by language for projects with 3+ languages (Topology 03+).

## Anti-patterns

- Logic inside `./dev` that should be in a script — split when subcommands grow past ~30 lines
- Scripts that call each other in deep chains — keep the call graph shallow; `./dev` is the orchestrator
- Bash scripts that should be Python (parsing, structured data) — at that point write Python
- Forgetting `set -euo pipefail` — silent failures bite
- Hardcoding service names that should come from compose project naming
