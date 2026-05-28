# Env precedence — the layering order

Env values come from three tiers. They load **lowest → highest priority**; later overrides earlier. The closer a source is to the runtime, the higher it wins.

## The three tiers

| Priority | Source | Holds | Committed? |
|---|---|---|---|
| 1 (lowest) | `root/.env` | **Shared / common** values: service URLs, ports, non-secret defaults several services agree on | no (`.env.example` is) |
| 2 | `root/<service>/.env` (e.g. `apps/api/.env`) | **Per-service**, mostly **secrets** (DB passwords, API keys) and service-specific overrides | no |
| 3 (highest) | **Real environment variables** | Exported in the shell / set by the orchestrator / CI / container `environment:` | n/a — never a file |

```
real env vars        (tier 3 — always win; how prod injects secrets)
        ▲ overrides
apps/api/.env        (tier 2 — per-service secrets + overrides)
        ▲ overrides
root/.env            (tier 1 — shared non-secret defaults)
```

Backends typically have one per-service `.env`; frontends have their own (`VITE_*` / `NEXT_PUBLIC_*`) — see `references/repo-setup/env-and-config/frontend-env-isolation.md`.

## The principle

**Secrets are injected as real env vars in prod, not committed to any file.** Files (`.env`) are a local-dev convenience and a home for non-secret shared defaults. In production the orchestrator (compose `environment:`, the platform's secret store, CI) sets the real env vars — tier 3 — and those always beat anything a file says. So the same code reads `os.environ["DB_PASSWORD"]` in both dev (from a file) and prod (from a real env var) with no branching.

## Loader semantics

Most dotenv loaders (e.g. python-dotenv) default to `override=False`: a value **already present in the real environment is not overwritten** by the `.env` file. That default is exactly what you want — real env wins (tier 3).

When you load **two** files (root then per-service), the more-specific file should beat the shared one — but **never** beat a real exported env var. Load files into a dict first, then let `os.environ` win:

```python
import os
from dotenv import dotenv_values

# tier 1 then tier 2: later file overrides earlier file
merged = {**dotenv_values("root/.env"), **dotenv_values("apps/api/.env")}

# tier 3 wins: real env vars override both files
config = {**merged, **os.environ}
```

The takeaway is the ordering — files merge most-specific-last, then real env overrides everything. (If you prefer `load_dotenv`, call it on the root file with `override=False`, then the service file with `override=True` over the root file's keys; just ensure no file load can clobber a pre-existing real env var.)

## How this composes with `config.yaml`

There are **two parallel override stacks** that meet at interpolation:

- **Env files** (this doc) → resolve a final set of env vars.
- Those vars get interpolated into `config.yaml` via `${VAR}` — see `references/repo-setup/env-and-config/yaml-var-interpolation.md`.
- **Config files** override separately: `config.local.yaml` overrides `config.yaml` — see `references/repo-setup/env-and-config/config-local-overrides.md`.

So env precedence decides *what `${VAR}` resolves to*; config precedence decides *which YAML layer wins*. They're orthogonal and meet only at the `${VAR}` substitution point.

## Anti-patterns

- Secrets in root `.env` — it's **shared**; put secrets in the per-service `.env` or inject them as real env vars in prod
- Committing any `.env` — gitignore them; commit `.env.example` as the contract
- A file overriding a real exported env var — breaks prod secret injection; real env must always win
- Duplicating the same URL in every service's `.env` — put it **once** in root `.env` and let services inherit it

## See also

- `references/repo-setup/env-and-config/root-env-shared-only.md`
- `references/repo-setup/env-and-config/per-service-config-yaml.md`
- `references/repo-setup/env-and-config/frontend-env-isolation.md`
- `references/repo-setup/env-and-config/secrets-matrix.md`
- `references/repo-setup/env-and-config/build-time-vs-runtime.md`
- `references/repo-setup/env-and-config/yaml-var-interpolation.md`
- `references/repo-setup/env-and-config/config-local-overrides.md`
