#!/usr/bin/env python
"""manager.py — the break-glass operator console. Run through `ctl manage`, or directly:

  uv run python manager.py ops create ops@example.com --super      # prompts for a password
  uv run python manager.py ops list
  uv run python manager.py ops disable ops@example.com
  uv run python manager.py ops reset-password ops@example.com --auto-password
  uv run python manager.py ops lockout ops@example.com --clear
  uv run python manager.py settings set max_workspaces 50

It runs WITHOUT the web auth flow: the deployer's direct console for bootstrapping and recovery
when the admin UI is unavailable — seed the first SuperAdmin, reset a password, flip a setting.
Access to it IS the security boundary. Every mutating action writes a row to `operator_audit`
(actor = "console", action, target, outcome). Operators are never deleted: disable sets
`disabled_at`, so the operator cannot authenticate while their audit history stays intact.

It lives at the backend root, beside `app/`, because it is a program, not a domain. It imports
the app's own loader (`app.config.settings`) and primitives (`app.core.security.hash_password`),
never a router: the same hashing and the same connection values as the running service, no
second copy.

Intent only — bodies are stubs. Keep the argparse tree; fill the coroutines against the real tables.
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import secrets
import sys

# from app.config import settings              # the one loader
# from app.core.security import hash_password  # argon2, the same primitive the login route uses
# import asyncpg, redis.asyncio as aioredis


# ── helpers ──────────────────────────────────────────────────────────────────

def _resolve_password(explicit: str | None, auto: bool) -> tuple[str, bool]:
    """Explicit flag > --auto-password (generated, printed once) > interactive prompt (twice)."""
    if explicit:
        return explicit, False
    if auto:
        return secrets.token_urlsafe(18), True
    pw = getpass.getpass("password: ")
    if pw != getpass.getpass("again: "):
        sys.exit("passwords do not match")
    return pw, False


async def _audit(conn, action: str, target: str, outcome: str) -> None:
    """INSERT INTO operator_audit (actor, action, target, outcome, at) — 'console' as the actor."""
    raise NotImplementedError


# ── operators ────────────────────────────────────────────────────────────────

async def ops_create(email: str, superadmin: bool, password: str, generated: bool) -> int:
    # hash with app.core.security.hash_password; INSERT operator; _audit("ops.create")
    # if generated: print the password ONCE, to stdout, nothing else on that line
    raise NotImplementedError

async def ops_list() -> int:
    # SELECT email, role, disabled_at ORDER BY email; print a table
    raise NotImplementedError

async def ops_set_disabled(email: str, disabled: bool) -> int:
    # UPDATE operator SET disabled_at = now() | NULL; _audit("ops.disable" | "ops.enable")
    raise NotImplementedError

async def ops_reset_password(email: str, password: str, generated: bool) -> int:
    # UPDATE password_hash; revoke refresh tokens in redis; _audit("ops.reset-password")
    raise NotImplementedError

async def ops_lockout(email: str, clear: bool) -> int:
    # read (or DEL with --clear) the login-throttle keys in redis; _audit("ops.lockout.clear") when cleared
    raise NotImplementedError


# ── platform settings ────────────────────────────────────────────────────────

async def settings_list() -> int:
    raise NotImplementedError

async def settings_get(key: str) -> int:
    raise NotImplementedError

async def settings_set(key: str, raw_json: str) -> int:
    # validate the key against the catalog; parse the value as JSON; UPSERT; _audit("settings.set")
    raise NotImplementedError


# ── argparse tree — keep this shape; `ctl manage` forwards argv verbatim ─────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="manager.py", description="break-glass operator console")
    sub = p.add_subparsers(dest="group", required=True)

    ops = sub.add_parser("ops", help="manage operators").add_subparsers(dest="op", required=True)
    c = ops.add_parser("create", help="create an operator"); c.add_argument("email")
    c.add_argument("--super", action="store_true", dest="superadmin")
    c.add_argument("--password"); c.add_argument("--auto-password", action="store_true")
    ops.add_parser("list", help="list operators")
    ops.add_parser("disable", help="block auth; never deletes").add_argument("email")
    ops.add_parser("enable", help="re-enable").add_argument("email")
    r = ops.add_parser("reset-password"); r.add_argument("email")
    r.add_argument("--password"); r.add_argument("--auto-password", action="store_true")
    lk = ops.add_parser("lockout", help="show or clear a login lockout"); lk.add_argument("email")
    lk.add_argument("--clear", action="store_true")

    st = sub.add_parser("settings", help="platform settings").add_subparsers(dest="op", required=True)
    st.add_parser("list"); st.add_parser("get").add_argument("key")
    s = st.add_parser("set"); s.add_argument("key"); s.add_argument("value", help="JSON")
    return p


def main(argv: list[str] | None = None) -> int:
    a = build_parser().parse_args(argv)
    if a.group == "ops":
        if a.op == "create":
            pw, gen = _resolve_password(a.password, a.auto_password)
            return asyncio.run(ops_create(a.email, a.superadmin, pw, gen))
        if a.op == "list":
            return asyncio.run(ops_list())
        if a.op in ("disable", "enable"):
            return asyncio.run(ops_set_disabled(a.email, a.op == "disable"))
        if a.op == "reset-password":
            pw, gen = _resolve_password(a.password, a.auto_password)
            return asyncio.run(ops_reset_password(a.email, pw, gen))
        if a.op == "lockout":
            return asyncio.run(ops_lockout(a.email, a.clear))
    if a.group == "settings":
        if a.op == "list":
            return asyncio.run(settings_list())
        if a.op == "get":
            return asyncio.run(settings_get(a.key))
        if a.op == "set":
            return asyncio.run(settings_set(a.key, a.value))
    return 2


if __name__ == "__main__":
    sys.exit(main())
