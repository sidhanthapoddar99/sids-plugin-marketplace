# Per-service `config.yaml` + `${VAR}` interpolation

Each backend gets its own `config.yaml` next to its code, holding **non-secret, service-specific** configuration with `${VAR}` placeholders for the bits that come from root `.env`. This keeps configs committed (no secrets in the YAML) while composing real values from env at load time.

## Why per-service, not root?

- A monorepo can have multiple backends (Layout 02), each with its own concerns. `database.pool_size` is a Python concern; `sync.broker_url` is a Rust concern. One root file would be soup.
- Each backend's `config.yaml` is self-documenting for that service.
- A service can be extracted to its own repo (Layout 03) without splitting a shared config file.

## Location

| Layout | Path(s) |
|---|---|
| 01 single-app | `apps/<tool>/config.yaml` |
| 02 mono 1be+1fe | `apps/backend/config.yaml` |
| 02 multi-backend | `apps/backend-python/config.yaml`, `apps/backend-rust/config.yaml`, … |
| 02 microservices mesh | `apps/<service>/config.yaml` |

## Shape (illustrative — not a mandated schema)

```yaml
# apps/backend/config.yaml — non-secret runtime config. Reads root .env via ${VAR}.
app:
  name: My App
  env: ${APP_ENV:-development}     # development | staging | production
  log_level: ${LOG_LEVEL:-info}
  host: 0.0.0.0
  port: ${PYTHON_PORT:-8000}
  workers: 4
database:
  url: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  pool_size: 20
  echo: false
redis:
  url: redis://default:${REDIS_PASSWORD}@redis:6379/0
auth:
  jwt_signing_key: ${JWT_SIGNING_KEY}
  jwt_algorithm: HS256
  oauth:
    google: { client_id: ${GOOGLE_OAUTH_CLIENT_ID}, client_secret: ${GOOGLE_OAUTH_CLIENT_SECRET} }
storage:
  s3: { endpoint: http://seaweed:8333, access_key: ${S3_ACCESS_KEY}, secret_key: ${S3_SECRET_KEY}, bucket: ${S3_BUCKET} }
```

None of these sections are mandatory — the skill cites them as concrete patterns when relevant, not as a prescribed schema.

## `${VAR}` substitution rules

| Pattern | Meaning |
|---|---|
| `${VAR}` | Value of `VAR`. **Error if unset** (fail loud). |
| `${VAR:-default}` | Value of `VAR`, or `default` if unset. |
| `${VAR:?error message}` | Value of `VAR`, or fail with the message if unset. |
| `$$VAR` (escape) | Literal `$VAR`. |

Mirrors POSIX shell / docker compose substitution — familiar, no new mental model. **Not** `{{ VAR }}`: that collides with Jinja/Mustache if the YAML is ever passed through a template engine, and `${VAR}` is easier to grep and type.

## Loading the config

Whatever the language: load YAML, run `${VAR}` substitution against `os.environ`, deep-merge overrides, parse into a typed object. Python (illustrative — use `pydantic` for typed access in real code):

```python
import os, re, yaml
from typing import Any

_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)(?::-(.+?))?(?::\?(.+?))?\}")

def _sub(m: re.Match) -> str:
    var, default, error = m.group(1), m.group(2), m.group(3)
    if var in os.environ and os.environ[var] != "":
        return os.environ[var]
    if default is not None:
        return default
    if error is not None:
        raise RuntimeError(f"config: {error}")
    raise RuntimeError(f"config references unset env var: {var}")   # fail loud, never silent empty

def load_yaml_config(path: str) -> dict[str, Any]:
    with open(path) as f:
        return yaml.safe_load(_PATTERN.sub(_sub, f.read()))
```

## `config.local.yaml` + multi-file merge

A sibling `config.local.yaml` (gitignored) takes precedence for local dev overrides; an optional committed `config.<env>.yaml` carries env-specific (non-secret) values:

```
config.yaml             # base, committed
config.<env>.yaml       # prod/staging override, committed (no secrets)
config.local.yaml       # dev override, gitignored
```

Deep-merge in order — `config.yaml` → `config.<mode>.yaml` → `config.local.yaml`, last wins:

```python
def load_with_overrides(base: str, mode: str | None) -> dict:
    cfg = load_yaml_config(base)
    if mode:
        p = base.replace(".yaml", f".{mode}.yaml")
        if os.path.exists(p): cfg = deep_merge(cfg, load_yaml_config(p))
    p = base.replace(".yaml", ".local.yaml")
    if os.path.exists(p): cfg = deep_merge(cfg, load_yaml_config(p))
    return cfg
```

(Deep merge: nested keys merge field by field; arrays replace whole.) See `00_env-precedence.md` for what belongs in `config.local.yaml` vs `.env.local`.

## When `${VAR}` is the wrong shape

For values that aren't single tokens (a nested dict, a list), branch at the loader level rather than in the YAML:

```python
config = load_yaml_config("config.yaml")
if os.environ.get("APP_ENV") == "production":
    config["database"]["pool_size"] = 50
```

Or split into mode-specific YAML (`config.production.yaml`) — but only if the differences are substantial.

## `config.template.yaml` (alternative)

Some projects keep a committed `config.template.yaml` (literal-with-placeholders) and let the wrapper copy it to `config.yaml` at first run. Fine when the config has per-deployment values that must be edited (not just secrets), or when env interpolation isn't desired. Default to the `${VAR}` approach unless you have a reason.

## Anti-patterns

- Putting secret values directly in `config.yaml` — that's what `${VAR}` + root `.env` are for.
- A single root `config.yaml` shared by multiple backends — leaks concerns.
- Letting `config.local.yaml` get committed — gitignore strictly.
- Allowing `${UNSET_VAR}` to silently substitute to empty — surface failures loudly.
- Inventing your own template syntax — stick to `${VAR}`.

## See also

- `00_env-precedence.md` — the three env tiers, root `.env` scope, `config.local.yaml` precedence
- `02_frontend-env-isolation.md` — why frontends use their own `.env`, not `config.yaml`/root `.env`
- `03_secrets-matrix.md` — where the secret values behind `${VAR}` actually live per environment
