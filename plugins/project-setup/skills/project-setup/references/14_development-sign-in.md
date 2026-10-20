# Development sign-in — `AUTH_ENABLED` and the reserved `default` user

A new project has no sign-in yet, and an automated test should not have to log in. So the template ships one switch, `AUTH_ENABLED`. With `FALSE`, a backend skips sign-in for a local request and acts as a reserved user named `default`, which a database migration creates. This page calls it the reserved user. With `TRUE`, every request needs a real credential, and every backend refuses the reserved user. Real sign-in can then come later without blocking the work before it.

The safety comes from the rules below, not from the default value: `FALSE` works only on this machine, containers always run `TRUE`, and the reserved user can never hold a credential. Template: `template/.env.template` (AUTHENTICATION), `template/apps/database/postgres/migrations/V2__users.sql` and `V3__development_identity.sql`, `template/apps/example-api-python/app/core/auth.py`, `template/apps/example-engine-rust/crates/common/src/auth_mode.rs` and `crates/auth/src/identity.rs`.

## The switch

```dotenv
#################### AUTHENTICATION ##########################
#################################################################

# Sign-in
# Read by every backend's loader; the browser never sees it. TRUE requires sign-in.
# FALSE: a local request with no credential acts as the reserved `default` user (V3 migration).
# Backends refuse FALSE on a non-loopback listener or public origin; compose always sets TRUE.
AUTH_ENABLED=FALSE
```

| Value | A request with no credential | A request with a credential |
|---|---|---|
| `FALSE` | Acts as the reserved user, when the request is local (see the checks below). Otherwise 401. | Verified as usual. It acts as its own owner, or gets 401. |
| `TRUE` | 401. | Verified as usual. A credential that names the reserved user gets 401. |

- Each backend reads the key through its `config.yaml` (`auth.enabled: ${AUTH_ENABLED}`). An absent key stops the start, as every unset reference does (`02_env.md` rule 8), so no backend guesses a mode.
- Accept `TRUE` or `FALSE` in any letter case. Fail on anything else, including `1`, `yes` and a blank, because a guessed mode is a wrong mode.
- The backend owns the switch. No browser parameter, header or frontend setting can turn sign-in off, because anything the browser sends, an attacker can send too.
- The template's default is `FALSE`, because the template ships no sign-in, and `TRUE` would block a new project until someone builds one.
- `compose.base.yaml` sets `AUTH_ENABLED: "TRUE"` as a literal for every backend, so no `.env` value or modifier changes it. A container listens on `0.0.0.0`, so `FALSE` could never start there anyway.

## The reserved user

`V2__users.sql` creates the `users` table. `V3__development_identity.sql` adds the marker column `development_identity` and the reserved row. Keep the two apart, so a project can delete the practice as one file, and so V3 shows the shape a project writes when it adopts the practice on a table it already has.

- The id is fixed: `00000000-0000-4000-8000-000000000001`. Every database built from the migrations holds the same row, so backends name the id as a constant, and test data can reference it.
- The username is `default`, and the row carries `development_identity = true`.
- A check constraint ties the marker to the fixed id. No ordinary account can carry the marker, and no ordinary account can take the id.
- A second check constraint keeps `password_hash` null on the reserved row, so no password form can match it.
- The row comes from a plain `INSERT`, with no `ON CONFLICT`. An existing account with that id or username fails the migration, so it never adopts, renames or resets an ordinary account.
- Backends read the row and never write it, because the migration is its one source, so every database holds the same row.
- Under `FALSE`, the api's `/ready` checks that the row exists, and names the migration when the row is missing. A missing row otherwise fails much later, at the first foreign key.
- The practice covers the user plane only. An operator plane (`07_security.md` § Operator identity) gets no reserved user, because operators come only from `ctl manage`.

## What each backend enforces

### At startup

The loader parses the switch. Then it refuses `FALSE` unless the listener host is loopback (`localhost`, `127.0.0.0/8` or `::1`) and `PUBLIC_URL`, when it is set, names a loopback host. The error names the setting to change. Any other host name fails the check, even one that resolves to loopback, because a name can resolve differently on another machine.

Under `FALSE`, the backend logs one warning at startup, so the mode shows in every log.

### For each request

1. The backend verifies a request's credential first, in both modes. A valid credential acts as its owner. An invalid or expired one gets 401 and never falls back to `default`, so a broken token cannot quietly become someone else. A credential that names the reserved user gets 401.
2. A request with no credential gets 401 under `TRUE`.
3. Under `FALSE`, a request with no credential acts as the reserved user only when every check below passes. Otherwise it gets 401.

| Check | It passes when | It stops |
|---|---|---|
| Peer address | The TCP peer is loopback. | A server bound wider than its settings say, such as `uvicorn --host 0.0.0.0` while `API_HOST=localhost`. |
| `Host` | The header is present and names a loopback host. | DNS rebinding: a public name that resolves to `127.0.0.1` in the developer's browser. |
| Forwarding headers | None is present, except an `X-Forwarded-Host` that names a loopback host. | A reverse proxy that relays a request from another machine. A dev server's own proxy may add `X-Forwarded-Host: localhost:<port>`, and Next.js rewrites do. The Vite proxy adds none. |
| `Origin` | The header is absent, or names a loopback host. `null` fails. | A page on another site that sends a request from the developer's browser. |
| `Sec-Fetch-Site` | The header is absent, or is not `cross-site`. | The same, for a request without `Origin`, such as an image tag. |

No check can see a proxy on the same host that adds no forwarding header and sends a loopback `Host`. That is why a deployed backend runs `TRUE`, inside a container or not (`09_production.md` § Checklist).

The checks live in one framework-free function per backend: `authenticate` in `app/core/auth.py` and `identity::authenticate` in the auth crate. A unit test can then prove them without a server. The framework glue gathers the peer, the header pairs and the token check, calls the function, and answers a refusal with 401. The opening comment of `auth.py` shows the FastAPI dependency. The opening comment of `identity.rs` describes the axum extractor. Pass every header pair to the function, duplicates included, because a duplicate `Host` or `X-Forwarded-Host` can hide a second value.

### The reserved user has no credential

Token issuance and password sign-in call `refuse_reserved` first. Token verification refuses the reserved id too. So no session or token for the reserved user can exist in either mode. A switch to `TRUE` therefore ends development sign-in at the next start. Nothing needs revoking, because the backend resolved each `FALSE` request on its own and issued nothing.

A project that mints a session or token in `FALSE` mode, such as a cookie for its frontend, marks it as a development credential. Its backends refuse that mark under `TRUE`, because otherwise a session from yesterday's development run outlives the switch.

The `me` response carries `development: true` for the reserved user, so the frontend can show a banner. The frontend never reads `AUTH_ENABLED`, because the backend owns the switch.

## Tests to write

The template ships these tests, and a project keeps them green: `app/core/test_auth.py` in the Python backend, and in the Rust engine the `tests` module in `crates/common/src/auth_mode.rs` and the file `crates/auth/src/identity/tests.rs`.

| Direction | The test proves |
|---|---|
| `FALSE` | A local request with no credential acts as the reserved user. A valid credential acts as its owner. An invalid credential, or one that names the reserved user, gets 401. |
| `FALSE`, not local | Each row of the request checks above refuses on its own: a non-loopback peer, a non-loopback or missing `Host`, each forwarding header, a foreign `Origin`, `cross-site`. |
| `TRUE` | A request with no credential gets 401. A credential that names the reserved user gets 401. An ordinary credential works from any address. |
| Startup | `FALSE` refuses a non-loopback listener and a non-loopback `PUBLIC_URL`. `TRUE` starts anywhere. A value other than `TRUE` or `FALSE` fails. |

A test of real sign-in, consent or account limits runs with `TRUE`, because a `FALSE` run never exercises them. An end-to-end suite runs against the built stack, where compose sets `TRUE`, so it signs in for real. A database test that proves the migration on a fresh database, and that a mode switch changes no user row, is integration work, and it waits for the user's word (`10c_dynamic-tests.md`).

## Adding real sign-in later

1. Write token issuance in `core/security.py` and the sign-in route in the users domain. Both call `refuse_reserved` first.
2. Pass the real token check to `authenticate`. The credential path already runs before the fallback, so nothing else changes.
3. Set `AUTH_ENABLED=TRUE` in `.env` once sign-in works. Automated tests that need no account still set `FALSE` for their own run.

The same split holds for any credential type. The backend verifies a session cookie on the same path as the bearer token, before the fallback. An external identity provider with its own reserved development account marks that account in its tokens. A backend refuses such a token under `TRUE`.

## Adopting it in an existing project

Write a forward migration shaped like V3 against the project's own user table: the marker column, the two check constraints and one plain `INSERT`. If the `INSERT` fails on a username collision, choose another reserved username. Never adopt the existing account, because its owner would then share it with every development run. Then copy the two rules files and their tests. Write the framework glue that their opening comments show.

## A project without accounts

Delete `V2__users.sql`, `V3__development_identity.sql`, the AUTHENTICATION section of `.env.template`, the `auth.enabled` lines and the rules files with their tests, before the first migration runs. Record the choice in the `Development sign-in` row of `AGENTS.md`.
