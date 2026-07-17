# Telemetry and audit — what to record and where

Owns what an app records for observability and accountability, and where that machinery sits in the skeleton. Four record types — request logs, audit events, error tracking, product telemetry — each with a placement rule. The unifying discipline: **telemetry is an adapter** (provider-swappable), and secrets/PII never land in plain logs.

## The four record types

| Record | What it is | Where it goes |
|---|---|---|
| **Structured request logs** | one structured line per request: method, path, status, latency, client IP, user id | stdout as JSON → the log pipeline |
| **Audit events** | first-class "who did what when" for state-changing / security-relevant actions | a durable audit store (a table / append-only log), not just logs |
| **Error tracking** | exceptions with stack + context | an error-tracking provider behind the adapter |
| **Product telemetry** | usage/analytics events | a telemetry provider behind the adapter, opt-out honored |

## Structured request logs

Log one structured record per request with **IP + user id** (the real client IP via forwarded headers, `references/3-app/09-security-hardening/00_edge-protection.md`). Emit JSON to stdout so the container log pipeline ships it (`references/3-app/10-deployment/00_serving.md` runs with `accesslog`/`errorlog` to stdout). Set a **retention** window and treat IP + user id as personal data — retention and access follow the same privacy rules as any PII.

## Audit events are first-class

Security- and compliance-relevant actions (login, permission change, data export, admin action, AI call) are recorded as **structured audit records** — actor, action, target, timestamp, outcome — in a durable store you can query, not scraped back out of text logs. This is distinct from request logging: request logs are operational and expire; audit events are accountability records with their own retention.

## Where it sits in the skeleton

- **Request logging + audit** → middleware in the backend `core/` (`references/3-app/02-backend/00_app-skeleton.md`), ahead of / around the handlers.
- **Telemetry + error tracking** → a **`telemetry` adapter module** — one internal interface, one adapter per provider, behind it. This is the adapter-modules pattern (`references/4-feature/feature-folders.md`): features call `telemetry.track(...)`, never a vendor SDK directly, so the provider is swappable and opt-out is enforced in one place.

## Product telemetry — as an adapter, opt-out honored

Product analytics goes through the same telemetry adapter. **Honor opt-out** at the adapter boundary — a user who declined analytics generates no events, enforced once in the adapter, not remembered at each call site. Swapping the analytics provider is replacing one adapter.

## Anti-patterns

- **Logging secrets or PII into plain logs** — no tokens, passwords, full AI prompt/response bodies, or raw personal data in text logs (`references/3-app/08-ai/02_ai-keys-and-safety.md`). Log identifiers and metadata.
- **Telemetry calls scattered through features** — vendor SDK calls sprinkled everywhere can't be swapped or opt-out-gated; route through the `telemetry` adapter.
- **Audit events living only in request logs** — logs expire and aren't queryable as records; audit needs a durable store.
- **Keying logs on the proxy IP** — read forwarded headers so IP means the real client.
- **No retention policy** — PII-bearing logs kept forever is a liability.

## See also

- `references/4-feature/feature-folders.md` — the adapter-modules pattern the telemetry adapter uses
- `references/3-app/02-backend/00_app-skeleton.md` — where request/audit middleware sits (`core/`)
- `references/3-app/09-security-hardening/00_edge-protection.md` — forwarded-header client IP
- `references/3-app/09-security-hardening/01_rate-limiting.md` — throttle events worth recording
- `references/3-app/08-ai/02_ai-keys-and-safety.md` — AI-call audit + no-PII-in-logs rule
- `references/3-app/10-deployment/00_serving.md` — stdout log wiring in production
