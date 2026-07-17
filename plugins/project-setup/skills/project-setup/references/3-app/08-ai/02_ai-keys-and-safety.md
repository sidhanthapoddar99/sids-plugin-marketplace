# AI keys and safety — usage, not storage

Owns how AI provider keys are **used** and how untrusted content is handled around models. Storage of the keys themselves — where the secret lives across dev/CI/prod, rotation — is owned by `references/2-repo/03-env-config/03_secrets-matrix.md`; this file assumes the key exists there and governs how code reaches for it and what guards sit around every AI call.

## Keys are backend-only

An AI provider key is a backend secret. It is loaded from the backend's config/env (`references/2-repo/03-env-config/01_per-service-config.md`) and used only in backend code.

- **Never in a frontend env scope.** A key placed in `VITE_*` or `NEXT_PUBLIC_*` is baked into the client bundle and is effectively published — this is the exact catastrophe the frontend-env-isolation owner exists to prevent (`references/2-repo/03-env-config/02_frontend-env-isolation.md`).
- Mobile/desktop clients are equally untrusted — a key shipped in an installable can be extracted.

## Clients reach providers through a backend proxy route

Browser, mobile, and desktop clients **never** call an AI provider directly. They call a backend route that holds the key and forwards the request. That proxy route is the single choke point where three controls live:

- **auth** — the caller is an authenticated user/session,
- **rate limiting + spend control** — per-user/per-key limits on the AI route, the strictest tier (`references/3-app/09-security-hardening/01_rate-limiting.md`),
- **logging/audit** — every AI call recorded (`references/3-app/09-security-hardening/02_telemetry-and-audit.md`).

No key in the client, no direct-to-provider calls from a browser — the proxy is the only path.

## Per-environment scoping and spend caps

- Use a **separate key per environment** (dev / staging / prod) so a leaked dev key can't touch prod spend and can be rotated independently.
- Set **provider-side spend caps / budget alerts** per key — an unbounded key behind a bug or an abusive client is a financial incident. The app-side rate limit and the provider-side cap are two independent backstops; set both.

## Prompt-injection posture

Any flow that feeds **user-supplied content** into a model that can call tools is a prompt-injection surface. Treat model output as **untrusted input**:

- **Allowlist tools** the model may call; never expose a raw shell/exec/eval tool.
- **Validate tool arguments** before executing — a tool call is a request, not a command to trust.
- **Never run model-produced strings** as code or SQL; parameterise and constrain.
- Keep the model's blast radius small — a tool reads/writes through the service layer with the same authorization checks a normal request gets, not a privileged bypass.

## Audit logging of AI calls

Record every AI call as a first-class event — who called, which model/route, token/cost, outcome — via the telemetry/audit adapter (`references/3-app/09-security-hardening/02_telemetry-and-audit.md`). Do **not** log full prompt/response bodies that may contain user PII into plain logs; log identifiers and metadata, and gate any content capture behind the same privacy rules as other request logging.

## Anti-patterns

- **Key in `VITE_*` / `NEXT_PUBLIC_*`** or shipped in a mobile/desktop build — it's published; rotate immediately (`references/2-repo/03-env-config/02_frontend-env-isolation.md`).
- **Client calling the provider directly** — no auth, no rate limit, no audit, key exposed.
- **One key across all environments** — a dev leak becomes a prod incident.
- **No spend cap** — a loop or abuse drains the budget silently.
- **A raw exec/eval tool** reachable by a model over user content — the classic injection foothold.
- **Trusting model output** as a command or query — validate and constrain like any external input.
- **Prompt/response bodies with PII in plain logs** — log metadata, not raw content.

## See also

- `references/2-repo/03-env-config/03_secrets-matrix.md` — where the key is stored + rotation (owner)
- `references/2-repo/03-env-config/02_frontend-env-isolation.md` — the frontend-env leak this prevents
- `references/3-app/09-security-hardening/01_rate-limiting.md` — the AI-proxy rate-limit tier
- `references/3-app/09-security-hardening/02_telemetry-and-audit.md` — AI-call audit logging
- `references/3-app/08-ai/01_agent-sdks.md` — the adapter the proxy route sits behind
