"""Who a request acts as, and the AUTH_ENABLED switch that allows development sign-in.

AUTH_ENABLED=TRUE: every request needs a credential, and no credential may name the reserved
identity. AUTH_ENABLED=FALSE: a request with no credential acts as the reserved `default` user
that the migration V3__development_identity.sql creates, but only a request made on this machine.
In both modes a credential, valid or not, is verified and never falls back to `default`, so an
expired token fails instead of quietly becoming someone else.

These rules import no framework, so a unit test proves them without a server. The loader in
config.py calls `parse_auth_enabled` and `check_listener`. The FastAPI dependency every router
uses feeds `authenticate` one request; write it with the project's loader and token check:

    async def current_principal(request: Request) -> Principal:
        peer = request.client.host if request.client else None
        try:
            return authenticate(settings.auth.enabled, peer, request.headers.items(), verify_token)
        except Refused as error:
            raise HTTPException(status_code=401, detail=str(error)) from error

Token issuance (core/security.py) and password sign-in (users/service.py) call `refuse_reserved`
first, so no credential for the reserved identity can exist in either mode.
"""

from __future__ import annotations

import ipaddress
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from uuid import UUID

# The fixed id from V3__development_identity.sql. The engine's auth crate holds the same value.
RESERVED_USER_ID = UUID("00000000-0000-4000-8000-000000000001")

# A dev server's proxy may add X-Forwarded-Host (Next.js rewrites do); any other forwarding
# header means a proxy relayed the request from somewhere else.
_FORWARDING = frozenset({"forwarded", "x-real-ip"})


class AuthSettingError(ValueError):
    """AUTH_ENABLED is not TRUE or FALSE, or it is FALSE where FALSE is unsafe."""


class Refused(Exception):
    """The request gets no principal. The dependency answers 401 with this message."""


@dataclass(frozen=True)
class Principal:
    user_id: UUID
    # True only for the reserved identity, so a `me` response can tell the UI to show it.
    development: bool = False


def parse_auth_enabled(raw: str) -> bool:
    """TRUE or FALSE in any case. Any other text fails, because a guessed mode is a wrong mode."""
    if raw.upper() == "TRUE":
        return True
    if raw.upper() == "FALSE":
        return False
    raise AuthSettingError(f"AUTH_ENABLED must be TRUE or FALSE, not {raw!r}")


def check_listener(auth_enabled: bool, host: str, public_url: str | None) -> None:
    """Refuse to start with FALSE unless the listener and any public origin are loopback."""
    if auth_enabled:
        return
    if not is_loopback_host(host):
        raise AuthSettingError(
            f"AUTH_ENABLED=FALSE needs a loopback listener, and this backend binds {host!r}. "
            "Set AUTH_ENABLED=TRUE, or bind 127.0.0.1."
        )
    if public_url and not is_loopback_host(url_host(public_url) or ""):
        raise AuthSettingError(
            "AUTH_ENABLED=FALSE refuses a public origin, and PUBLIC_URL names a non-loopback "
            "host. Set AUTH_ENABLED=TRUE, or comment out PUBLIC_URL."
        )


def is_loopback_host(host: str) -> bool:
    """`localhost`, 127.0.0.0/8 or ::1. A name that only resolves to loopback does not count."""
    if host.lower() == "localhost":
        return True
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped is not None:
        return address.ipv4_mapped.is_loopback
    return address.is_loopback


def authority_host(authority: str) -> str | None:
    """The host of `host`, `host:port` or `[v6]:port`. None when the text is anything else."""
    if not authority or any(c in authority for c in "@/?#\\ \t,"):
        return None
    if authority.startswith("["):
        end = authority.find("]")
        if end < 0:
            return None
        host, rest = authority[1:end], authority[end + 1 :]
    else:
        host, colon, port = authority.partition(":")
        rest = colon + port
    port = rest[1:]
    if rest and not (rest.startswith(":") and port.isascii() and port.isdigit()):
        return None
    return host or None


def url_host(url: str) -> str | None:
    """The host of an http(s) URL or Origin header value. None when it is not one."""
    scheme, separator, rest = url.partition("://")
    if not separator or scheme.lower() not in ("http", "https"):
        return None
    return authority_host(rest.split("/", 1)[0])


def request_is_local(peer: str | None, headers: Iterable[tuple[str, str]]) -> bool:
    """True when nothing says the request came from off this machine or from a web page elsewhere.

    The peer address catches a server bound wider than the settings say. The Host header catches
    DNS rebinding. Forwarding headers catch a reverse proxy. Origin and Sec-Fetch-Site catch a
    page on another site that the developer's browser is visiting.
    """
    pairs = [(name.lower(), value) for name, value in headers]
    if peer is None or not is_loopback_host(peer):
        return False
    if not any(name == "host" for name, _ in pairs):
        return False
    return all(_header_is_local(name, value) for name, value in pairs)


def _header_is_local(name: str, value: str) -> bool:
    if name in ("host", "x-forwarded-host"):
        return is_loopback_host(authority_host(value) or "")
    if name == "origin":
        return is_loopback_host(url_host(value) or "")
    if name == "sec-fetch-site":
        return value.lower() != "cross-site"
    return name not in _FORWARDING and not name.startswith("x-forwarded-")


def refuse_reserved(user_id: UUID) -> None:
    """The reserved identity has no credential, so any credential that names it is refused."""
    if user_id == RESERVED_USER_ID:
        raise Refused("the reserved development identity cannot sign in or hold a credential")


def authenticate(
    auth_enabled: bool,
    peer: str | None,
    headers: Iterable[tuple[str, str]],
    verify: Callable[[str], UUID],
) -> Principal:
    """The principal for one request.

    `verify` takes a bearer token and returns its user id, or raises Refused. A project that
    adds a session cookie verifies it on the same path as the bearer token, before the fallback.
    """
    pairs = [(name.lower(), value) for name, value in headers]
    credentials = [value for name, value in pairs if name == "authorization"]
    if credentials:
        scheme, _, token = credentials[0].partition(" ")
        if len(credentials) > 1 or scheme.lower() != "bearer" or not token:
            raise Refused("send one Authorization: Bearer <token> header")
        user_id = verify(token)
        refuse_reserved(user_id)
        return Principal(user_id)
    if auth_enabled:
        raise Refused("sign in required")
    if not request_is_local(peer, pairs):
        raise Refused("development sign-in serves only requests made on this machine")
    return Principal(RESERVED_USER_ID, development=True)
