# Build-time vs runtime env vars

Every env var the project uses falls into one of two categories. Misclassifying one is a silent foot-gun.

## Build-time (baked into the artefact)

- Substituted at **build** time, **stays in the artefact**
- Cannot change after build without rebuilding
- For Vite / Next / Astro frontends: any `VITE_*` / `NEXT_PUBLIC_*` falls here
- For Rust binaries: `env!("MY_VAR")` macros, sqlx `DATABASE_URL` at compile time for offline checks

If a build-time value should differ between dev and prod, you need **two builds** (one image per environment, or one image per locale). Trying to "swap" at runtime doesn't work.

## Runtime (read on boot, can change)

- Read from `os.environ` / `std::env::var` / `process.env` **at boot**
- Container's `env_file:` / `environment:` populates these
- Backend services (Python, Rust, Go, server-side Node) — most config falls here

This is the safe, flexible category. Default to runtime unless a build-time reason forces otherwise.

## Examples

| Variable | Build-time or runtime | Why |
|---|---|---|
| `DATABASE_URL` (backend) | Runtime | Different per environment, doesn't bake into image |
| `VITE_API_BASE_URL` | Build-time | Bundle is static; cannot change after build |
| `VITE_SENTRY_DSN` | Build-time | Same |
| `NEXT_PUBLIC_FEATURE_FLAG` | Build-time | Bundle ships this to clients |
| `POSTGRES_PASSWORD` | Runtime | Loaded by container at boot via env_file |
| `JWT_SIGNING_KEY` | Runtime | Same |
| `APP_VERSION` | Either — usually build-time | Often baked from git ref at build |
| `SQLX_OFFLINE` (Rust) | Build-time | Compile-time database check toggle |

## How docker compose passes them

Compose has three slots:

1. `args:` under `build:` — build-time, available during `docker build`
2. `environment:` — runtime, set inside the container
3. `env_file:` — runtime, loaded from a file at boot

```yaml
services:
  frontend:
    build:
      context: ./apps/frontend
      args:
        VITE_API_BASE_URL: ${VITE_API_BASE_URL}    # build-time
        VITE_SENTRY_DSN: ${VITE_SENTRY_DSN}
  backend:
    build: ./apps/backend
    env_file:
      - .env.production                             # runtime
    environment:
      LOG_LEVEL: ${LOG_LEVEL}                       # runtime
```

The frontend's Dockerfile must `ARG VITE_API_BASE_URL` and pass it into the build. Compose's `args:` doesn't propagate automatically.

## turbo.json `globalEnv` for multi-frontend builds

In a turborepo monorepo, list every build-time env var in `turbo.json`:

```json
{
  "globalEnv": [
    "NODE_ENV",
    "VITE_API_BASE_URL",
    "VITE_WEB_BASE_URL",
    "VITE_ADMIN_BASE_URL",
    "VITE_SENTRY_DSN"
  ]
}
```

Turbo's cache key includes these. Forgetting one means a build that should rebuild doesn't.

## Confirmation step in `/ps-setup`

For each variable the user lists, ask:

> Does `<VAR>` differ between environments?
> - Yes, and it must change without rebuilding → runtime
> - Yes, but we accept rebuilding per-env → build-time
> - No, it's the same everywhere → either, doesn't matter

For each `VITE_*` / `NEXT_PUBLIC_*`, also confirm: "this ends up visible to the browser — safe to expose?"

## Anti-patterns

- Trying to read `VITE_*` at runtime (e.g. via a config server) — you've defeated the purpose; either use runtime injection via a `<script>` tag with a config object the SPA reads on boot, or accept build-time
- Same value baked into the bundle as a `VITE_*` and also passed via runtime env to the backend — pick one; if both are needed, they'll drift
- Forgetting to add a new `VITE_*` to `turbo.json` `globalEnv` → cache stale
