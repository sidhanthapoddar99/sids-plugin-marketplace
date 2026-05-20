# Frontend env isolation — keep backend secrets out of the bundle

This is the security-critical convention. Get it wrong and you ship `DATABASE_URL` to every browser visiting your site.

## The rule

**Each frontend has its own `.env` file**, scoped to that frontend, containing **only** the variables it needs at build time. Backend secrets must never appear there.

```
apps/frontend/.env           # ← VITE_* / NEXT_PUBLIC_* ONLY
apps/frontend/.env.example   # ← committed, the contract for the frontend
```

The root `.env` is **not** read by the frontend's build process. Vite, Next, and similar bundlers ignore anything that doesn't have their prefix anyway, but the discipline of physically separating files prevents accidents.

## Why bundlers expose env vars

Frontend code runs in the user's browser. To inject a value at build time (e.g. an API base URL), the bundler **literally substitutes the value** into the JS bundle:

```js
// source:
const url = import.meta.env.VITE_API_BASE_URL;
// bundle:
const url = "/api";
```

If you put `DATABASE_URL` in a Vite-readable file, Vite will happily inline it into JS that ships to the browser. The user views source → they have your DB credentials.

## Which prefix exposes what

| Bundler | Prefix that exposes to client |
|---|---|
| Vite | `VITE_*` |
| Next.js | `NEXT_PUBLIC_*` |
| Create React App (legacy) | `REACT_APP_*` |
| Remix | `PUBLIC_*` (varies by version) |
| Astro | `PUBLIC_*` (in client-rendered components) |

Anything **without** the prefix stays server-side (for SSR frameworks) or simply isn't accessible. Anything **with** the prefix gets baked into the bundle.

## What belongs in `apps/<frontend>/.env`

| ✅ Yes — safe to expose | ❌ No — must NOT appear |
|---|---|
| API base URL (`VITE_API_BASE_URL=/api`) | Database URL or creds |
| App name, version, environment label | Backend service-to-service secrets |
| Public OAuth client IDs (Google, Microsoft — these are designed to be public) | OAuth client secrets |
| Analytics keys that are designed to be public (PostHog public key, Sentry DSN — front-half) | Stripe secret keys, API write keys |
| Feature flags that are not security-sensitive | JWT signing keys |
| `VITE_APP_BASE_PATH` | `OPENAI_API_KEY` (route requests through your backend, never expose) |

## Example

```bash
# apps/frontend/.env.example
VITE_API_BASE_URL=/api
VITE_APP_NAME=My App
VITE_APP_ENV=development
VITE_SENTRY_DSN=https://public-key@sentry.io/12345
VITE_POSTHOG_KEY=phc_public_key_for_analytics
VITE_GOOGLE_OAUTH_CLIENT_ID=12345-abc.apps.googleusercontent.com
```

```bash
# apps/frontend/.env (gitignored)
VITE_API_BASE_URL=/api
VITE_APP_NAME=My App (local)
VITE_APP_ENV=development
VITE_SENTRY_DSN=
VITE_POSTHOG_KEY=
VITE_GOOGLE_OAUTH_CLIENT_ID=12345-abc.apps.googleusercontent.com
```

## Runtime vs build-time for SPA

For a pure SPA (Vite + React), **everything in `.env` is build-time**. The bundle is built once and serves every visitor. You cannot change a value without rebuilding.

For an SSR framework (Next.js, Remix, Astro):

- Build-time: `NEXT_PUBLIC_*` (still baked into the bundle)
- Runtime (server-only): un-prefixed vars accessible in server components / API routes only

The skill should ask whether SSR is in play and route accordingly.

## Confirmation step in `/ps-setup`

When walking the user through `apps/<frontend>/.env.example`, **read each line aloud and confirm**:

> `VITE_API_BASE_URL` — this gets baked into the JS bundle and visible to all users. Safe? Yes.
> `VITE_STRIPE_PUBLIC_KEY` — Stripe public key, designed to be exposed. Safe? Yes.
> `VITE_STRIPE_SECRET_KEY` — STOP. Secret keys must NOT be in a `VITE_*` var. Route Stripe API calls through your backend.

Catching this once is worth annoying the user.

## Real-world reference

- `plane`'s `turbo.json` `globalEnv` lists every `VITE_*` — confirms the per-frontend pattern. Each `apps/<frontend>` has its own env.
- atheneum's frontend is single, with its own `apps/frontend/.env` scope (though atheneum predates this convention and may have root `VITE_*` keys to clean up).

## Anti-patterns

- `cp .env apps/frontend/.env` — copies backend secrets into the frontend bundle. Disaster.
- Symlinking root `.env` into `apps/frontend/` — same disaster.
- A "shared" .env file at root that backend and frontend both read — pick one scope per variable
- Hand-waving the build-time vs runtime distinction — for each var, confirm explicitly
