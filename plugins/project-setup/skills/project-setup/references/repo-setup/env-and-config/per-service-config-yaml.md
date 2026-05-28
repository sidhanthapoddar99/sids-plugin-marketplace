# Per-service `config.yaml`

Each backend gets its own `config.yaml` next to its code. The root `.env` holds shared secrets; the service's `config.yaml` holds **non-secret, service-specific** configuration with `${VAR}` placeholders for the bits that come from `.env`.

## Why per-service, not root?

- A monorepo can have multiple backends (Layout 02), each with its own concerns. `database.pool_size` is a Python backend concern; `sync.broker_url` is a Rust backend concern. Mixing them in a root file would be a soup.
- Each backend's `config.yaml` becomes self-documenting for that service.
- Service can be extracted to its own repo (Layout 03) without splitting a shared config file.

## Location

| Layout | Path(s) |
|---|---|
| 01 single-app | `apps/<tool>/config.yaml` |
| 02 mono 1be+1fe | `apps/backend/config.yaml` |
| 02 multi-backend | `apps/backend-python/config.yaml`, `apps/backend-rust/config.yaml`, … |
| 02 multi-frontend | `apps/<app>/config.yaml` if needed |
| 02 microservices mesh | `apps/<service>/config.yaml` |

## Shape (illustrative — not mandatory)

```yaml
# apps/backend/config.yaml
# Non-secret runtime config. Reads root .env via ${VAR}.

app:
  name: My App
  env: ${APP_ENV}          # development | staging | production
  log_level: ${LOG_LEVEL}  # debug | info | warn | error
  host: 0.0.0.0
  port: ${PYTHON_PORT}
  workers: 4

database:
  url: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  pool_size: 20
  pool_max_overflow: 10
  echo: false

redis:
  url: redis://default:${REDIS_PASSWORD}@redis:6379/0

auth:
  jwt_signing_key: ${JWT_SIGNING_KEY}
  jwt_algorithm: HS256
  jwt_ttl_seconds: 86400
  oauth:
    google:
      client_id: ${GOOGLE_OAUTH_CLIENT_ID}
      client_secret: ${GOOGLE_OAUTH_CLIENT_SECRET}

email:
  provider: smtp
  smtp:
    host: ${SMTP_HOST}
    port: ${SMTP_PORT}
    username: ${SMTP_USERNAME}
    password: ${SMTP_PASSWORD}
    from_address: ${SMTP_FROM}

search:
  meilisearch:
    url: http://meilisearch:7700
    api_key: ${MEILI_MASTER_KEY}

storage:
  s3:
    endpoint: http://seaweed:8333
    access_key: ${S3_ACCESS_KEY}
    secret_key: ${S3_SECRET_KEY}
    bucket: ${S3_BUCKET}
```

**This shape is illustrative.** None of these sections are mandatory. The skill cites them as concrete patterns when relevant, not as a prescribed schema.

## Loading the config

Whatever language: load YAML, run `${VAR}` substitution against `os.environ`, parse into a typed object.

Python (illustrative):

```python
# apps/backend/app/config.py
import os, re, yaml
from pydantic import BaseModel

VAR_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")

def _interpolate(text: str) -> str:
    def replace(match):
        var = match.group(1)
        if var not in os.environ:
            raise RuntimeError(f"config.yaml references unset env var: {var}")
        return os.environ[var]
    return VAR_PATTERN.sub(replace, text)

def load_config(path: str = "config.yaml") -> dict:
    with open(path) as f:
        raw = f.read()
    local_path = path.replace(".yaml", ".local.yaml")
    if os.path.exists(local_path):
        with open(local_path) as f:
            raw_local = _interpolate(f.read())
        # naive merge — replace with deep_merge in real code
        return {**yaml.safe_load(_interpolate(raw)), **yaml.safe_load(raw_local)}
    return yaml.safe_load(_interpolate(raw))
```

See `yaml-var-interpolation.md` for the substitution rules.

## `config.local.yaml`

A sibling file `config.local.yaml` (gitignored) takes precedence over `config.yaml` for local dev overrides:

```yaml
# apps/backend/config.local.yaml — local dev only, gitignored
app:
  log_level: debug

database:
  echo: true        # log all SQL
```

The loader deep-merges `config.local.yaml` on top of `config.yaml` if it exists.

## `config.template.yaml` pattern (alternative)

Some projects keep a committed `config.template.yaml` (the literal-with-placeholders version) and let the wrapper copy it to `config.yaml` at first run. This is fine when:

- The config has values that must be edited per-deployment (not just secrets)
- Or when running in environments where env interpolation isn't desired

Default to the `${VAR}` approach unless you have a reason.

## Anti-patterns

- Putting secrets directly in `config.yaml` — that's what `${VAR}` and root `.env` are for
- Single root `config.yaml` shared by multiple backends — leaks concerns
- Letting `config.local.yaml` get committed — gitignore strictly
- Schema-validating `config.yaml` at load time but failing silently on missing env vars — fail loud
