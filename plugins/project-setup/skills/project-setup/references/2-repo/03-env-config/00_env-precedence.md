# Env precedence — where a value comes from and who wins

Env values come from three tiers, loading **lowest → highest priority** (later overrides earlier). The closer a source is to the runtime, the higher it wins. Files (`.env`) are a local-dev convenience and a home for non-secret shared defaults; **secrets are injected as real env vars in prod, never committed.**

## The three tiers

| Priority | Source | Holds | Committed? |
|---|---|---|---|
| 1 (lowest) | `root/.env` | **Shared / common** values: service URLs, ports, non-secret defaults several services agree on | no (`.env.example` is) |
| 2 | `<service>/.env` (e.g. `apps/api/.env`) | **Per-service**, mostly **secrets** (DB passwords, API keys) and service-specific overrides | no |
| 3 (highest) | **Real environment variables** | Exported in the shell / set by the orchestrator / CI / container `environment:` | n/a — never a file |

```
real env vars        (tier 3 — always win; how prod injects secrets)
        ▲ overrides
apps/api/.env        (tier 2 — per-service secrets + overrides)
        ▲ overrides
root/.env            (tier 1 — shared non-secret defaults)
```

Backends typically have one per-service `.env`; frontends have their own (`VITE_*` / `NEXT_PUBLIC_*`) — see `02_frontend-env-isolation.md`.

**The principle:** the same code reads `os.environ["DB_PASSWORD"]` in both dev (from a file) and prod (from a real env var) with no branching. In production the orchestrator (compose `environment:`, a secret store, CI) sets tier-3 env vars, and those always beat anything a file says.

## Loader semantics

Most dotenv loaders default to `override=False`: a value **already present in the real environment is not overwritten** by `.env`. That default is exactly what you want — real env wins (tier 3). When loading **two** files (root then per-service), the more-specific file beats the shared one, but **never** beats a real exported env var:

```python
import os
from dotenv import dotenv_values
merged = {**dotenv_values("root/.env"), **dotenv_values("apps/api/.env")}  # tier 1 then 2: later file wins
config = {**merged, **os.environ}                                          # tier 3: real env overrides both
```

Files merge most-specific-last, then real env overrides everything. (With `load_dotenv`: root with `override=False`, then the service file with `override=True` over the root keys — just ensure no file load clobbers a pre-existing real env var.)

The same rule applies to shell loaders. The ctl toolkit's `require_env`/`load_env_file` (`scripts/common/_lib.sh`) loads `.env` **skip-if-set** — a key already present in the real environment is never overwritten — which is `override=False` for bash. `set -a; source .env; set +a` is the tempting one-liner, but `source` assigns unconditionally, so a file value would beat an inline override (`NGINX_PORT=8085 ./ctl up`) or a CI-injected secret: the anti-pattern below. The trade: the skip-if-set loop only handles plain `KEY=value` lines (no multi-line values or command substitution — desirable constraints for an env file anyway), where `source` would parse quoting.

## Root `.env` — shared / common vars only

The root `.env` is **not** a global dumping ground. It holds only what's shared across services or needed by docker compose orchestration.

| ✅ Belongs at root `.env` | ❌ Does NOT belong |
|---|---|
| DB creds (`POSTGRES_USER/PASSWORD/DB/PORT`), Redis (`REDIS_PASSWORD/PORT`) | **Frontend-public vars** (`VITE_*`, `NEXT_PUBLIC_*`) → `apps/<frontend>/.env` |
| Auth secrets shared across backends (`JWT_SIGNING_KEY`, `ENCRYPTION_KEY_*`) | **Per-service non-secrets** → that service's `config.yaml` |
| Shared external API keys (only if multiple services consume) | **ML experiment hyperparameters** → `configs/<experiment>.yaml` |
| Compose orchestration (`DATA_DIR`, `DOMAIN`, `TZ`, port mappings) | |
| Per-service runtime hints (`PYTHON_PORT`, `RUST_PORT`) so compose can map them | |

### `.env.example` is the contract

`.env` is gitignored; **`.env.example` is committed** and is the contract every developer / CI / prod machine reads first. Comments are not optional — the file is the contract for humans, not just machines.

```bash
# my-app — environment contract
# Copy to .env and fill the blanks. Secrets must be generated, not invented: openssl rand -hex 32
# Anything marked REQUIRED must be set before `ctl` will start.

# ─── Database ───
POSTGRES_USER=myapp
POSTGRES_PASSWORD=               # REQUIRED — openssl rand -hex 32
POSTGRES_DB=myapp
POSTGRES_PORT=5432
# ─── Redis ───
REDIS_PASSWORD=                  # REQUIRED — openssl rand -hex 32
# ─── Auth ───
JWT_SIGNING_KEY=                 # REQUIRED — openssl rand -hex 32
# ─── Service ports (host-side, for dev) ───
PYTHON_PORT=8000
# ─── Compose ───
DATA_DIR=../data                 # bind-mount root — relative to docker/ (see 04-docker/00_docker-overview.md path discipline)
DOMAIN=localhost
TZ=Asia/Kolkata
```

### The derived files

| File | Purpose | Gitignored? |
|---|---|---|
| `.env` | Local dev values | yes |
| `.env.example` | The committed contract | no |
| `.env.production` | Production values, loaded as compose `env_file:` | yes |
| `.env.local` | Optional dev override (rare; usually `config.local.yaml` covers it) | yes |

### How `.env` is consumed

1. **docker compose** auto-loads root `.env` for `${VAR}` interpolation in compose files.
2. **per-service `config.yaml`** interpolates `${VAR}` from root `.env` — see `01_per-service-config.md`.
3. **`ctl`** loads `.env` at the top via `require_env` — skip-if-set, so a real exported env var is never overwritten (see Loader semantics above); `ctl setup` fills it and `ctl status` diffs it against `.env.example` — see `references/2-repo/05-ctl-scripts-tooling/01_script-usage.md`.
4. **Frontends do not read root `.env`** — see `02_frontend-env-isolation.md`.

## `config.local.yaml` — local-only overrides

A sibling to `config.yaml` (gitignored) that takes precedence in local dev, letting a developer tweak settings without editing the committed config.

```
apps/backend/
├── config.yaml          # committed, the base
└── config.local.yaml    # gitignored, your overrides
```

```yaml
# apps/backend/config.local.yaml
app:      { log_level: debug }     # base says info; I want debug locally
database: { echo: true }           # log all SQL
redis:    { url: redis://localhost:6379/15 }   # db 15 to not collide with other projects
features: { new_search_ui: true }  # feature flag for in-progress work
```

What goes in it: things that vary **per-developer** (log levels, local DB on a non-standard port, feature toggles, mock endpoints). Things that vary **per-environment** go in `config.<env>.yaml` or env vars.

**Loading order:** `config.yaml` → `config.<env>.yaml` (committed, env-specific) → `config.local.yaml` (gitignored, dev-only). Deep merge — nested keys merge field by field; arrays replace whole. Gitignore `*.local.yaml` / `**/*.local.yaml`.

**Why not just `.env.local`?** `.env.local` is for runtime env vars; `config.local.yaml` is for structured config (arrays/objects/nested keys). They coexist — a dev typically has both: `.env.local` with personal API keys, `config.local.yaml` with preferred log levels. Secrets go in `.env.local` and are referenced from YAML via `${VAR}`, never written into `config.local.yaml`.

## Two parallel override stacks meet at interpolation

- **Env files** (this doc) resolve a final set of env vars.
- Those vars interpolate into `config.yaml` via `${VAR}` — see `01_per-service-config.md`.
- **Config files** override separately: `config.local.yaml` over `config.yaml`.

Env precedence decides *what `${VAR}` resolves to*; config precedence decides *which YAML layer wins*. Orthogonal, meeting only at the `${VAR}` substitution point.

## Anti-patterns

- Secrets in root `.env` — it's **shared**; put secrets in the per-service `.env` or inject as real env vars in prod.
- Committing any `.env` — gitignore them; commit `.env.example`.
- A file overriding a real exported env var — breaks prod secret injection; real env must always win.
- Duplicating the same URL in every service's `.env` — put it **once** in root `.env` and inherit.
- Frontend-public vars at root — leaks if a backend bundles them.
- Per-service non-secret config in `.env` — that's what `config.yaml` is for.
- Committing `config.local.yaml`, or encoding secrets in it — defeats the purpose; secrets go in `.env.local`.

## See also

- `01_per-service-config.md` — `config.yaml` + `${VAR}` interpolation
- `02_frontend-env-isolation.md` — build-time vs runtime + keeping secrets out of the client bundle
- `03_secrets-matrix.md` — where secrets live across dev / CI / prod / vault
- `references/2-repo/05-ctl-scripts-tooling/01_script-usage.md` — `ctl setup` / `ctl status` (the `require_env` guard, the schema diff)
