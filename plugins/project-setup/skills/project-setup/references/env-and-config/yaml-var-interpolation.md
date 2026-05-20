# YAML config with `${VAR}` interpolation

`config.yaml` files reference root `.env` via `${VAR_NAME}` placeholders, substituted at load time. Keeps configs committed (no secrets in the YAML) while still composing the real values from env.

## Substitution rules (recommended)

| Pattern | Meaning |
|---|---|
| `${VAR}` | Replace with the value of `VAR`. Error if unset. |
| `${VAR:-default}` | Replace with the value of `VAR`, or `default` if unset. |
| `${VAR:?error message}` | Replace with `VAR`, or fail with the message if unset. |
| `$$VAR` (escape) | Literal `$VAR`. |

Mirrors POSIX shell expansion — familiar, no new mental model.

## Example

```yaml
# apps/backend/config.yaml

app:
  name: My App
  env: ${APP_ENV:-development}
  log_level: ${LOG_LEVEL:-info}
  port: ${PYTHON_PORT:-8000}

database:
  url: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD:?missing POSTGRES_PASSWORD}@${POSTGRES_HOST:-postgres}:${POSTGRES_PORT:-5432}/${POSTGRES_DB}
  pool_size: ${DB_POOL_SIZE:-20}

redis:
  url: redis://default:${REDIS_PASSWORD}@${REDIS_HOST:-redis}:${REDIS_PORT:-6379}/0
```

Loader walks the YAML, replaces tokens, and parses to a typed config object.

## Python reference loader

```python
import os, re, yaml
from typing import Any

_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)(?::-(.+?))?(?::\?(.+?))?\}")

def _sub(match: re.Match) -> str:
    var, default, error = match.group(1), match.group(2), match.group(3)
    if var in os.environ and os.environ[var] != "":
        return os.environ[var]
    if default is not None:
        return default
    if error is not None:
        raise RuntimeError(f"config: {error}")
    raise RuntimeError(f"config references unset env var: {var}")

def _interpolate_text(text: str) -> str:
    return _PATTERN.sub(_sub, text)

def load_yaml_config(path: str) -> dict[str, Any]:
    with open(path) as f:
        raw = _interpolate_text(f.read())
    return yaml.safe_load(raw)
```

(Use `pydantic` for typed access in real code; this snippet is the substitution part only.)

## Why `${VAR}` and not `{{ VAR }}`?

- `${VAR}` matches POSIX shell and docker compose's own substitution — fewer mental models.
- `{{ VAR }}` collides with Jinja, Mustache, and template engines if the YAML is ever passed through one.
- Easier to grep, easier to type.

The Notes mentioned both; the skill commits to `${VAR}`.

## When `${VAR}` is the wrong shape

For values that aren't single tokens (e.g. a nested dict, a list), use env-driven branching at the loader level rather than YAML interpolation:

```python
config = load_yaml_config("config.yaml")
if os.environ.get("APP_ENV") == "production":
    config["database"]["pool_size"] = 50
```

Or break into mode-specific YAML files (`config.production.yaml`) — but only if the differences are substantial.

## Multi-file merge

```
config.yaml             # base, committed
config.local.yaml       # dev override, gitignored
config.production.yaml  # prod override, committed (no secrets)
```

Loader deep-merges in order: `config.yaml` → `config.<mode>.yaml` → `config.local.yaml`. Last wins.

```python
def load_with_overrides(base_path: str, mode: str | None) -> dict:
    cfg = load_yaml_config(base_path)
    if mode:
        mode_path = base_path.replace(".yaml", f".{mode}.yaml")
        if os.path.exists(mode_path):
            cfg = deep_merge(cfg, load_yaml_config(mode_path))
    local_path = base_path.replace(".yaml", ".local.yaml")
    if os.path.exists(local_path):
        cfg = deep_merge(cfg, load_yaml_config(local_path))
    return cfg
```

## Anti-patterns

- Putting actual secret values in `config.yaml` "temporarily" — they get committed
- Using `${VAR}` for runtime-changing values that should be env-only — defeats the purpose
- Allowing `${UNSET_VAR}` to silently substitute to empty string — surface failures loudly
- Inventing your own template syntax — stick to `${VAR}`
