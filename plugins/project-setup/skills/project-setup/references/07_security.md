# Security — the floor every product has

The rules that hold regardless of size. Each row names where the control lives, because a control with no owner is a control nobody runs. Secrets storage and rotation: `02_env.md`. The edge: `03_routing.md`. Prod hardening: `09_production.md`.

## The floor

| Concern | Where | Rule |
|---|---|---|
| Edge protection | nginx, or a host proxy in front | TLS, body size limit, proxy timeouts aligned with the app's, security headers (`Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options`, `Referrer-Policy`), gzip or brotli. |
| Protection tier | recorded in `AGENTS.md` | Pick by exposure, escalate on evidence: **none** (internal tools, no unauthenticated write surface) → **captcha** (any public form or auth endpoint) → **managed WAF** (Cloudflare or equivalent in front of the origin: managed rules, bot scoring, DDoS absorption; a public product with real abuse exposure or a compliance need). Behind a WAF the app reads `CF-Connecting-IP` / `X-Forwarded-For` for the real client, or every limit and log keys on the proxy. |
| Captcha | public forms: signup, login, password reset, contact, anything unauthenticated that writes or costs | Cloudflare Turnstile, or the best privacy-respecting option at the time; check before choosing. The site key is a build constant in the frontend; the secret key lives in `.env.secrets`; a backend dependency verifies the token before the handler runs and fails closed. A widget with no server verification blocks nothing. Never on authenticated routes. |
| Rate limiting | two layers: coarse per-IP request caps at nginx (`limit_req`) on public endpoints; per-user limits in the backend router, a dependency in `core/` | Keyed on the user id or API key; raw IP only for unauthenticated routes (NAT lumps users, one user rotates IPs). Per-route tiers in `config.yaml`: baseline for reads, stricter on auth endpoints, strictest on AI-proxy routes, a separate quota for bulk and export. Redis-backed when there is more than one worker or replica; an in-process counter under-counts by the worker multiple. The contract: `429` with `Retry-After`, optionally `X-RateLimit-Limit` / `-Remaining`. |
| Auth tokens | `core/security.py` | Short-lived signed access tokens, opaque refresh tokens in Redis, argon2 passwords. One `JWT_SIGNING_KEY` shared with every validator. |
| Operator identity | `manager.py` at the admin backend's root, run by `ctl manage` | Never reachable through public signup or OAuth. The first SuperAdmin is seeded from the host with `ctl manage ops create --super`; resets and lockouts go the same way; every action audited. A different admin look is not a reason for a second backend; a different identity plane is (`03_routing.md` case 7). `08_ctl.md`. |
| Audit | a domain slice (`audit/`) | Durable, queryable records: actor, action, target, outcome, time. Distinct from request logs. Never a secret or a body in a log. Logs carry a retention policy: IP plus user id is PII. |
| Telemetry and error tracking | one adapter in `core/` | Swappable provider, opt-out enforced once at the boundary. Not day one: metrics first (`/metrics`), tracing when there is more than one service, error tracking and an uptime pinger as pain dictates. |
| Secrets | `.env.secrets`, `config.yaml` as `${VAR}` | Never a literal in code or config, never a build arg, never in an image layer. A secret that reaches git is rotated. Prod files `chmod 600`, owned by the app user. A secrets manager (Vault, a cloud KMS) is the graduation path, not day one; the loader's skip-if-set rule is what makes the swap invisible. |
| Dependencies | `ctl gate audit` | `pip-audit`, `bun audit`, `cargo audit`, `govulncheck`, gitleaks on every ladder run. `10_testing.md`. |

## AI and third-party keys

| Rule | Detail |
|---|---|
| Keys are backend-only | `.env.secrets`, read by the one loader. A key in `VITE_*` / `NEXT_PUBLIC_*` or shipped in a mobile or desktop build is published; rotate it. |
| One proxy route | Browser, mobile and desktop clients never call a provider. They call a backend route that holds the key. That route is the choke point for auth, the strictest rate-limit tier, a per-user quota, and audit. |
| One key per environment | Dev, staging and prod each get their own provider key, so a leak in one cannot spend in another and rotation is independent. Provider-side spend caps and budget alerts on every key: the app-side limit and the provider cap are two independent backstops; set both. |
| Provider adapters | One adapter per provider behind one internal interface; engine code never names a provider (`06_backend.md`). Streaming, tool dispatch and retries stay inside the adapter. |
| Prompts are files | Versioned, in one place the feature owns (`prompts/`), diff-reviewable, never an f-string three calls deep. Model IDs and generation parameters live in `config.yaml`, never in code; swapping a model is a config edit. Golden evals beside the feature's tests must pass before a prompt or model change ships. |
| Audit every call | Who, which model and route, tokens and cost, outcome. Metadata, not bodies: a prompt with user PII in a plain log is a leak. |

## Prompt injection

Any flow that feeds user-supplied content to a model that can call tools is an injection surface. Model output is untrusted input:

- Allowlist the tools the model may call. Never a raw shell, exec or eval tool; never one mega "run this" tool. Discrete, typed tools.
- Validate every tool argument before executing. A tool call is a request, not a command.
- Never run model-produced strings as code or SQL. Parameterise and constrain.
- A tool reads and writes through the service layer with the same authorisation a normal request gets. Never a privileged bypass.
- The tool surface of an MCP server is a versioned contract: adding is additive, renaming or changing a schema is breaking. Pin third-party MCP servers to an exact version; a remote MCP server is public surface with the full edge posture.

## Tripwires

| Seen | Broken rule |
|---|---|
| a captcha widget with no backend verify call | fail closed at the backend |
| rate limit keyed on IP for a logged-in route | key on user or API key |
| `429` without `Retry-After` | the throttle contract |
| a provider name in engine code | adapter per provider |
| a prompt inline in a service | prompts are files |
| a model ID in code | config, not code |
| one AI key in every environment | one key per environment |
| an `exec`-shaped tool reachable by a model | allowlisted, typed tools |
| a password hash or token in a log line | never a secret in a log |
| `manager.py` reachable through a published port | host access is the boundary |
