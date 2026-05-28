# Secrets matrix — dev / CI / prod / vault future

Where secrets live across the lifecycle. Pick consciously for each layer.

## Matrix

| Layer | Where secrets live | What's committed |
|---|---|---|
| **Local dev** | `.env`, `.env.local`, `config.local.yaml` (all gitignored) | `.env.example` (contract, blanks for secrets) |
| **CI (open source)** | GitHub Actions secrets (encrypted at rest, masked in logs) | Workflow files referencing `${{ secrets.NAME }}` |
| **CI (private/self-hosted)** | Self-hosted runner env / encrypted secrets file | Workflow files |
| **Prod (compose-on-vm)** | `.env.production` on the host (chmod 600, not committed), loaded via `env_file:` | `compose.prod.yaml` referencing the file path |
| **Prod (future — Vault)** | Vault / 1Password Connect / cloud secrets manager | Vault path references in config |

## Local dev rules

1. **`.env.example` is the contract.** Every secret key listed, with a comment explaining how to generate it. Required keys marked.
2. **Generation instructions at the top of `.env.example`**:

   ```
   # Secrets must be generated, not invented:
   #   openssl rand -hex 32           # for any HMAC/JWT key
   #   openssl rand -base64 32        # for passwords
   #   openssl rand -base64 16        # for shorter tokens
   ```

3. **`.env` and friends MUST be in `.gitignore`**:

   ```
   .env
   .env.local
   .env.production
   *.local.yaml
   ```

4. **`ctl` refuses to start if `.env` has unfilled required keys.** See `references/repo-setup/runtime/script-usage.md` for the `require_env` helper.

## CI rules

- **Open source GitHub Actions**: secrets stored in repo settings → Actions → Secrets, referenced as `${{ secrets.POSTGRES_PASSWORD }}`. Never echo to logs.
- **Self-hosted**: runner machine has `.env.ci` (root-readable only); workflow sources it.
- **PR builds**: do NOT receive secrets by default — be explicit about which secrets are required and use `pull_request_target` carefully.

## Prod rules (compose-on-VM, current default)

```
/srv/my-app/
├── .env.production           # chmod 600, owned by root or app user
├── docker-compose.yaml -> /home/user/my-app/docker/compose.yaml
├── docker-compose.prod.yaml -> /home/user/my-app/docker/compose.prod.yaml
└── ctl                       # `ctl up app edge --config=prod` runs the deploy
```

The secrets-relevant part: the `--config=prod` config switches the compose `--env-file` to `.env.production` (it also pins image tags + resource limits). The exact assembled `docker compose` line is the dispatcher's to own — see `references/repo-setup/runtime/script-usage.md`.

Or, with `env_file:` declared inside each service in the compose:

```yaml
services:
  backend:
    env_file:
      - .env.production
```

## Prod rules (future — Vault / 1Password)

When the project graduates from compose-on-VM:

1. Secrets live in Vault.
2. Each service has a Vault path it reads on boot.
3. `config.yaml` references **Vault paths** instead of `${VAR}`:

   ```yaml
   database:
     password: vault://kv/data/my-app/db#password
   ```

4. A loader plugin resolves `vault://` URIs.
5. `.env.production` is no longer needed.

Document the migration path; don't build for Vault on day one if the project is one VM.

## Rotation policy (the part most projects skip)

For each secret, document:

| Secret | Rotation cadence | Recovery procedure |
|---|---|---|
| `JWT_SIGNING_KEY` | Quarterly (or on suspicion of leak) | Rotate → restart auth service → old tokens invalidated |
| `POSTGRES_PASSWORD` | Annually | Update Postgres → update `.env.production` → restart backend |
| `STRIPE_SECRET_KEY` | On suspicion only | Rotate in Stripe dashboard → update `.env.production` |
| `ENCRYPTION_KEY_*` | Never (rotating breaks encrypted-at-rest data; key-roll requires re-encryption migration) | Document the re-encrypt procedure |

This goes in `docs/data/secrets-matrix.md` or equivalent — the skill recommends creating it.

## What to ASK the user during `/ps-setup`

- Open source or private? (affects CI defaults)
- Single prod machine, multiple, or cloud-managed?
- Vault present or planned?
- Any secrets already in a vault that should be referenced rather than copied to `.env`?

Without these answers, default to local + GitHub Actions + compose-on-VM and document the gap.

## Anti-patterns

- Committing `.env` "just this once" — git history is forever; rotate the secrets if it happens
- Storing secrets in `config.yaml` as literals "because env vars are annoying" — `${VAR}` from `.env` exists for a reason
- A "shared dev .env" passed around Slack — use 1Password / Bitwarden shared vaults
- Skipping `.env.example` entirely — the contract matters more than the values
