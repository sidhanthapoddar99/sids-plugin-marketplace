# Edge protection — bot and abuse defense in front of public apps

Owns the app-level decision of how much bot/abuse protection sits in front of a public app, and where the enforcement lives. Reverse-proxy / edge **infrastructure** (nginx, Traefik, the expose tiers) is L2 — `references/2-repo/04-docker/04_proxy-and-exposure.md`; this file owns the posture that runs on top of it: WAF/proxy choice, captcha placement, and which routes need it.

## The tiers — pick one consciously

| Tier | What it is | Choose when |
|---|---|---|
| **None** | no bot layer; rely on auth + rate limits | internal tools, no unauthenticated write surface |
| **Turnstile / captcha** | a challenge on public write endpoints, verified backend-side | any public form or auth endpoint that unauthenticated users can hit |
| **Full WAF** | Cloudflare (or equivalent) proxy in front of the origin — managed rules, bot scoring, DDoS absorption | public product with real abuse/DDoS exposure, or a compliance requirement |

Escalate by evidence: start at the tier the exposure warrants, move up when abuse appears. Record the chosen tier in the project CLAUDE.md.

## Cloudflare / WAF posture

When a managed WAF is in scope, the origin sits **behind** it: the proxy terminates TLS, applies managed rules and bot scoring, and forwards to the edge (nginx/Traefik) that `references/2-repo/04-docker/04_proxy-and-exposure.md` owns. The app must read `X-Forwarded-For` / `CF-Connecting-IP` to see the real client IP (the same forwarded-header discipline the proxy doc describes) — otherwise rate limits and logs key on the proxy, not the user.

## Captcha / Turnstile — where the verification lives

The widget in the page is only half of it. **Verification happens backend-side**: the client submits the challenge token, and a backend middleware calls the provider's verify endpoint before the handler runs. A frontend-only widget with no server verification is theater — it blocks nothing.

- Placement: a backend middleware/dependency on the protected routes, ahead of the handler, keyed off the submitted token.
- Fail closed: no valid token → reject before the write.

## Which routes need it

Protect **unauthenticated endpoints that write or cost**:

- signup / registration,
- login (throttle credential-stuffing — pairs with the auth rate-limit tier, `references/3-app/09-security-hardening/01_rate-limiting.md`),
- contact / feedback / any public form that creates records or sends mail,
- password reset and other unauthenticated state-changing routes,
- anything unauthenticated that triggers cost (an AI-proxy route reachable pre-auth — but prefer requiring auth there, `references/3-app/08-ai/02_ai-keys-and-safety.md`).

Authenticated, read-only, internal routes generally don't need a captcha — auth + rate limits carry them.

## Anti-patterns

- **Frontend-only captcha** with no backend verification — decorative, blocks nothing.
- **Captcha on everything** — friction on authenticated/read routes drives users off; protect the write/abuse surface, not the whole app.
- **Not reading forwarded headers** behind a WAF/proxy — every limit and log keys on the proxy IP.
- **WAF as the only layer** — it complements app auth + rate limits; it does not replace them.
- **Picking a tier by default** instead of by exposure — record why the tier fits.

## See also

- `references/2-repo/04-docker/04_proxy-and-exposure.md` — the reverse-proxy/edge infrastructure (L2 owner)
- `references/3-app/09-security-hardening/01_rate-limiting.md` — the limits that pair with captcha on auth routes
- `references/3-app/09-security-hardening/02_telemetry-and-audit.md` — recording blocked/abusive requests
- `references/3-app/08-ai/02_ai-keys-and-safety.md` — protecting cost-bearing AI routes
