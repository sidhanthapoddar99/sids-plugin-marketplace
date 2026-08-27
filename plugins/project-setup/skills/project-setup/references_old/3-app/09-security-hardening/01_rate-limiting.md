# Rate limiting — the layers and what each owns

Owns the app-level rate-limiting decision: where per-user / per-key business limits live (backend middleware), and the response contract when a caller is throttled. Connection-level limits at the reverse proxy are L2 (`references/2-repo/04-docker/04_proxy-and-exposure.md`); this file owns the application layer.

## The three layers — put each limit where it belongs

| Layer | Enforces | Owner |
|---|---|---|
| **Edge / WAF** | volumetric / DDoS, bot scoring | `references/3-app/09-security-hardening/00_edge-protection.md` |
| **Reverse proxy** | coarse connection / request-rate caps per IP | L2 — `references/2-repo/04-docker/04_proxy-and-exposure.md` |
| **App middleware** | per-user / per-API-key **business** limits | **this file** |

The app owns the limits that require knowing *who* is calling and *what* — those can't be expressed at the proxy, which sees only IPs.

## App-owned limits — placement

A rate-limit middleware sits in the backend skeleton ahead of the handlers (a FastAPI dependency / middleware in `core/`, `references/3-app/02-backend/00_app-skeleton.md`), keyed on the authenticated **user id or API key**, not the raw IP (many users share one NAT'd IP; one user rotates IPs).

- **Single instance** → an in-process counter is coherent.
- **Multiple instances / workers** → the limit state must be shared, so back it with **Redis** (`references/3-app/04-database/06_redis.md`) — an in-process counter per worker under-counts by the worker multiple. This is the same worker-count coupling the cache decision has (`references/3-app/10-deployment/00_serving.md`).

## Sane defaults — tier by route sensitivity

| Route class | Relative limit |
|---|---|
| Authenticated read (normal API) | baseline |
| Auth endpoints (login / signup / reset) | **stricter** — throttle credential stuffing; pairs with captcha (`references/3-app/09-security-hardening/00_edge-protection.md`) |
| AI-proxy routes | **strictest** — they carry real per-call cost + spend risk (`references/3-app/08-ai/02_ai-keys-and-safety.md`) |
| Bulk / export | low, with a separate quota |

Drive the numbers from config so they tune per environment; record the chosen limits.

## The 429 contract

When a caller is throttled, return **HTTP 429** with a **`Retry-After`** header (seconds or HTTP-date). Optionally include `X-RateLimit-Limit` / `X-RateLimit-Remaining` so well-behaved clients self-pace. A throttle without `Retry-After` forces clients to guess and hammer — the contract is: reject with 429, tell them when to retry.

## Anti-patterns

- **Rate-limiting on IP for authenticated routes** — NAT lumps users together; key on user/API-key.
- **In-process counters across N workers/instances** — each worker counts independently; the real limit is N× your intent. Use Redis when multi-instance.
- **429 without `Retry-After`** — clients retry blindly and amplify load.
- **One global limit for every route** — auth and AI routes need their own stricter tiers.
- **Restating proxy connection limits here** — those are L2; this layer is per-user/per-key business limits.

## See also

- `references/2-repo/04-docker/04_proxy-and-exposure.md` — proxy-level connection limits (L2 owner)
- `references/3-app/09-security-hardening/00_edge-protection.md` — captcha + WAF that pair with auth-route limits
- `references/3-app/09-security-hardening/02_telemetry-and-audit.md` — recording throttle events
- `references/3-app/04-database/06_redis.md` — Redis-backed shared limit state
- `references/3-app/10-deployment/00_serving.md` — why worker/instance count drives the Redis decision
