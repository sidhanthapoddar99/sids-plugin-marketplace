# Root `.env` — shared / common vars only

The root `.env` is **not** a global dumping ground. It holds only the variables that are shared across services or that the docker compose orchestration needs.

## What belongs at root `.env`

| Category | Examples |
|---|---|
| Database creds | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT` |
| Redis | `REDIS_PASSWORD`, `REDIS_PORT` |
| Auth secrets shared across backends | `JWT_SIGNING_KEY`, `ENCRYPTION_KEY_*` |
| Shared external API keys | `OPENAI_API_KEY`, `STRIPE_SECRET_KEY` (only if multiple services consume) |
| Compose orchestration | `DATA_DIR`, `DOMAIN`, `TZ`, port mappings |
| Per-service runtime hints | `PYTHON_HOST`, `PYTHON_PORT`, `RUST_HOST`, `RUST_PORT` (so compose can map them) |

## What does NOT belong at root `.env`

- **Frontend-public vars** (`VITE_*`, `NEXT_PUBLIC_*`) — these belong in `apps/<frontend>/.env`. See `frontend-env-isolation.md`.
- **Per-service non-secrets** — these belong in that service's `config.yaml`.
- **Experiment hyperparameters** (ML) — these belong in `configs/<experiment>.yaml`.

## `.env.example` is the contract

`.env` itself is gitignored. **`.env.example` is committed** and is the contract every developer / CI / prod machine reads first.

Format `.env.example`:

```bash
# my-app — environment contract
#
# Copy to .env and fill in the blanks. Secrets must be generated, not invented:
#   openssl rand -hex 32
#
# Anything marked REQUIRED must be set before `./dev` will start.
# Anything else has a sensible default in compose / config.yaml.

# ─── Database ─────────────────────────────────────────────
POSTGRES_USER=myapp
POSTGRES_PASSWORD=               # REQUIRED — `openssl rand -hex 32`
POSTGRES_DB=myapp
POSTGRES_PORT=5432

# ─── Redis ────────────────────────────────────────────────
REDIS_PASSWORD=                  # REQUIRED — `openssl rand -hex 32`
REDIS_PORT=6379

# ─── Auth ─────────────────────────────────────────────────
JWT_SIGNING_KEY=                 # REQUIRED — `openssl rand -hex 32`

# ─── Service ports (host-side, for dev) ───────────────────
PYTHON_PORT=8000
RUST_PORT=8080

# ─── Compose ──────────────────────────────────────────────
DATA_DIR=./data                  # where bind-mounts live
DOMAIN=localhost
TZ=Asia/Kolkata
```

Comments are not optional — the file is the contract for humans, not just machines.

## How `.env` is consumed

1. **docker compose** — auto-loads root `.env` for `${VAR}` interpolation in compose files
2. **per-service `config.yaml`** — interpolates `${VAR}` from root `.env` (see `yaml-var-interpolation.md`)
3. **`./dev` wrapper** — sources `.env` at the top (`set -a; source .env; set +a`)
4. **Frontends** — **do not read root `.env`** (see `frontend-env-isolation.md`)

## Three derived files

| File | Purpose | Gitignored? |
|---|---|---|
| `.env` | Local dev values | yes |
| `.env.example` | Contract for committed |
| `.env.production` | Production values, loaded as compose `env_file:` | yes |
| `.env.local` | Optional dev override (rare; usually `config.local.yaml` covers this) | yes |

## Bootstrap

The `./dev` wrapper's first job is to check `.env` exists and matches `.env.example`'s keys:

```bash
require_env() {
  if [[ ! -f .env ]]; then
    if [[ -f .env.example ]]; then
      echo ".env not found — copying from .env.example."
      echo "Fill the REQUIRED blanks, then re-run."
      cp .env.example .env
      exit 1
    fi
    die ".env missing and no .env.example exists."
  fi
  set -a
  source .env
  set +a
}
```

A `./dev check-env` subcommand diffs `.env`'s keys against `.env.example` and reports missing or extra ones.

## Anti-patterns

- Storing frontend public vars at root — leaks if a backend service accidentally bundles them
- Treating `.env.example` as a one-time thing — keep it in lockstep with `.env`
- Putting per-service non-secret config in `.env` — that's what `config.yaml` is for
- Committing `.env` "just for development" — don't
