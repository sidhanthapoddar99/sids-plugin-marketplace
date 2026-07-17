# Build-time vs runtime env + frontend isolation

This is the **security-critical** convention. Get it wrong and you ship `DATABASE_URL` to every browser visiting your site. It rests on one distinction — *when* a var is bound — so start there.

## Build-time vs runtime — the underlying distinction

Every env var falls into one of two categories; misclassifying one is a silent foot-gun.

- **Build-time** — substituted at **build** time and **baked into the artefact**; cannot change without rebuilding. Frontend `VITE_*` / `NEXT_PUBLIC_*`; Rust `env!(...)` macros / `SQLX_OFFLINE`. If a build-time value must differ between dev and prod, you need **two builds** — you can't swap it at runtime.
- **Runtime** — read from `os.environ` / `std::env::var` / `process.env` **at boot**; populated by the container's `env_file:` / `environment:`. Most backend config. The safe, flexible category — **default to runtime** unless a build-time reason forces otherwise.

| Variable | Category | Why |
|---|---|---|
| `DATABASE_URL`, `POSTGRES_PASSWORD`, `JWT_SIGNING_KEY` (backend) | Runtime | Loaded by the container at boot; differs per env, never baked |
| `VITE_API_BASE_URL`, `VITE_SENTRY_DSN`, `NEXT_PUBLIC_*` | Build-time | Bundle is static; ships to clients; cannot change after build |
| `APP_VERSION` | Usually build-time | Often baked from git ref at build |
| `SQLX_OFFLINE` (Rust) | Build-time | Compile-time database-check toggle |

### How docker compose passes them

```yaml
services:
  frontend:
    build:
      context: ./apps/frontend
      args:
        VITE_API_BASE_URL: ${VITE_API_BASE_URL}    # build-time — needs ARG in the Dockerfile; not auto-propagated
        VITE_SENTRY_DSN: ${VITE_SENTRY_DSN}
  backend:
    build: ./apps/backend
    env_file: [ .env.production ]                   # runtime
    environment:
      LOG_LEVEL: ${LOG_LEVEL}                       # runtime
```

Three slots: `args:` under `build:` = build-time (during `docker build`); `environment:` = runtime (set in the container); `env_file:` = runtime (loaded at boot). The frontend's Dockerfile must `ARG VITE_API_BASE_URL` and pass it into the build.

## The isolation rule

**Each frontend has its own `.env` file**, scoped to that frontend, containing **only** the build-time vars it needs. Backend secrets must never appear there.

```
apps/frontend/.env           # ← VITE_* / NEXT_PUBLIC_* ONLY
apps/frontend/.env.example   # ← committed, the contract for the frontend
```

The root `.env` is **not** read by the frontend's build. Bundlers ignore unprefixed vars anyway, but physically separating files prevents accidents.

### Why bundlers expose env vars

Frontend code runs in the user's browser, so the bundler **literally substitutes the value** into the JS at build time:

```js
const url = import.meta.env.VITE_API_BASE_URL;   // source
const url = "/api";                              // bundle
```

Put `DATABASE_URL` in a Vite-readable file and Vite inlines it into JS that ships to the browser. View-source → they have your DB credentials.

| Bundler | Prefix that exposes to client |
|---|---|
| Vite | `VITE_*` |
| Next.js | `NEXT_PUBLIC_*` |
| Create React App (legacy) | `REACT_APP_*` |
| Remix / Astro | `PUBLIC_*` (varies by version) |

Anything **with** the prefix gets baked into the bundle; anything **without** stays server-side (SSR) or is inaccessible.

### What belongs in `apps/<frontend>/.env`

| ✅ Safe to expose | ❌ Must NOT appear |
|---|---|
| API base URL (`VITE_API_BASE_URL=/api`) | Database URL or creds |
| App name, version, environment label | Backend service-to-service secrets |
| **Public** OAuth client IDs (designed to be public) | OAuth client **secrets** |
| Public analytics keys (PostHog public, Sentry DSN front-half) | Stripe secret keys, API write keys |
| Non-sensitive feature flags | JWT signing keys, `OPENAI_API_KEY` (route through backend) |

```bash
# apps/frontend/.env.example
VITE_API_BASE_URL=/api
VITE_APP_NAME=My App
VITE_APP_ENV=development
VITE_SENTRY_DSN=https://public-key@sentry.io/12345
VITE_GOOGLE_OAUTH_CLIENT_ID=12345-abc.apps.googleusercontent.com
```

## SPA vs SSR

For a pure SPA (Vite + React), **everything in `.env` is build-time** — built once, served to every visitor; you can't change a value without rebuilding. For an SSR framework (Next.js, Remix, Astro): `NEXT_PUBLIC_*` is still baked into the client bundle, but **un-prefixed vars stay server-only** (server components, route handlers, `next.config`). Ask whether SSR is in play and route accordingly.

### Vite vs Next.js — the env-split contrast

| | **Vite** (SPA) | **Next.js** (SSR / app router) |
|---|---|---|
| Client-visible | `VITE_*` baked into the bundle | `NEXT_PUBLIC_*` baked into the client bundle |
| Server-only | none — no server runtime | un-prefixed vars (route handlers, server components, `next.config`) |
| Dev proxy to backend | Vite dev server proxies `/api/*` (target from env) | `next.config` `rewrites()` — server-side proxy, can read server-only env |
| Backend URL exposure | necessarily public if the browser needs it | can stay **server-side** via `rewrites()` |

The sharp point: **with Vite, anything the browser touches is necessarily public**; **with Next, a backend URL used only in `rewrites()` need not be `NEXT_PUBLIC_*`** and can stay hidden. Either way, secrets never go in a client-exposed var. See `references/2-repo/deployment/proxy-and-exposure.md` and `references/3-app/frontend/framework-variants.md`.

## `turbo.json` `globalEnv` (multi-frontend builds)

In a turborepo monorepo, list every build-time env var so Turbo's cache key includes them — forgetting one means a build that should rebuild doesn't:

```json
{ "globalEnv": ["NODE_ENV", "VITE_API_BASE_URL", "VITE_WEB_BASE_URL", "VITE_ADMIN_BASE_URL", "VITE_SENTRY_DSN"] }
```

The `globalEnv` config body (alongside the rest of the turbo/pnpm/bun config) is owned by `references/3-app/frontend/workspaces-mechanics.md`; the point that matters *here* is that every build-time var must be registered or the cache goes stale.

## Confirmation step in `/ps-setup`

For each variable, classify and (for client vars) confirm exposure — read each line aloud:

> Does `<VAR>` differ between environments and must change *without* rebuilding? → runtime. Accept rebuilding per-env? → build-time. Same everywhere? → either.
>
> `VITE_API_BASE_URL` — baked into the bundle, visible to all users. Safe? Yes.
> `VITE_STRIPE_PUBLIC_KEY` — Stripe public key, designed to be exposed. Safe? Yes.
> `VITE_STRIPE_SECRET_KEY` — **STOP.** Secret keys must NOT be in a `VITE_*` var. Route Stripe calls through your backend.

Catching this once is worth annoying the user.

## Anti-patterns

- `cp .env apps/frontend/.env` or symlinking root `.env` into the frontend — copies backend secrets into the bundle. Disaster.
- A "shared" root `.env` both backend and frontend read — pick one scope per variable.
- Trying to read `VITE_*` at runtime via a config server — you've defeated the purpose; inject a config object via a `<script>` tag the SPA reads on boot, or accept build-time.
- Same value baked as `VITE_*` and also passed via runtime env to the backend — they'll drift; pick one.
- Forgetting a new `VITE_*` in `turbo.json` `globalEnv` → stale cache.
- Hand-waving the build-time vs runtime distinction — for each var, confirm explicitly.

## See also

- `env-precedence.md` — the three env tiers; why frontends don't read root `.env`
- `per-service-config.md` — backend `config.yaml` + `${VAR}` (the runtime-config counterpart)
- `secrets-matrix.md` — where secrets live across dev / CI / prod
- `references/2-repo/deployment/proxy-and-exposure.md`, `references/3-app/frontend/framework-variants.md` — proxy config detail
