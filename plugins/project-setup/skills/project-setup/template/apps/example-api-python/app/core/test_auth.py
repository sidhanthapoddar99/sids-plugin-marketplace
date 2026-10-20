"""Development sign-in in both directions, and the loopback rules that keep FALSE local."""

from uuid import UUID

import pytest

from app.core.auth import (
    RESERVED_USER_ID,
    AuthSettingError,
    Principal,
    Refused,
    authenticate,
    check_listener,
    parse_auth_enabled,
)

ORDINARY = UUID("6f1c2e9a-3b7d-4c55-9e2a-0d4b8f7a1c33")
LOCAL = [("Host", "localhost:8000")]


def verify(token: str) -> UUID:
    """A stand-in for the project's token check: two known tokens, everything else invalid."""
    tokens = {"ordinary-token": ORDINARY, "reserved-token": RESERVED_USER_ID}
    if token not in tokens:
        raise Refused("invalid token")
    return tokens[token]


def bearer(token: str) -> list[tuple[str, str]]:
    return [*LOCAL, ("Authorization", f"Bearer {token}")]


@pytest.mark.parametrize(
    ("raw", "enabled"), [("TRUE", True), ("true", True), ("FALSE", False), ("False", False)]
)
def test_the_switch_reads_true_or_false_in_any_case(raw: str, enabled: bool) -> None:
    assert parse_auth_enabled(raw) is enabled


@pytest.mark.parametrize("raw", ["", "1", "0", "yes", "off", " TRUE", "FALSE "])
def test_any_other_switch_value_fails(raw: str) -> None:
    with pytest.raises(AuthSettingError, match="AUTH_ENABLED must be TRUE or FALSE"):
        parse_auth_enabled(raw)


# Disabled: a local request with no credential acts as the reserved identity.


@pytest.mark.parametrize("peer", ["127.0.0.1", "127.8.9.10", "::1", "::ffff:127.0.0.1"])
def test_disabled_gives_a_local_request_the_reserved_identity(peer: str) -> None:
    assert authenticate(False, peer, LOCAL, verify) == Principal(RESERVED_USER_ID, development=True)


@pytest.mark.parametrize(
    "extra",
    [
        ("Origin", "http://localhost:5173"),
        ("Sec-Fetch-Site", "same-site"),
        ("X-Forwarded-Host", "localhost:3000"),
        ("X-Forwarded-Host", "127.0.0.1"),
    ],
)
def test_disabled_accepts_a_local_browser_or_dev_server_proxy(extra: tuple[str, str]) -> None:
    assert authenticate(False, "127.0.0.1", [*LOCAL, extra], verify).development


def test_disabled_still_verifies_a_credential_and_acts_as_its_owner() -> None:
    assert authenticate(False, "127.0.0.1", bearer("ordinary-token"), verify) == Principal(ORDINARY)


@pytest.mark.parametrize("token", ["expired-token", "reserved-token"])
def test_disabled_never_turns_a_bad_credential_into_the_reserved_identity(token: str) -> None:
    with pytest.raises(Refused):
        authenticate(False, "127.0.0.1", bearer(token), verify)


@pytest.mark.parametrize("value", ["Basic abc", "Bearer", "Bearer ", "token"])
def test_disabled_refuses_a_malformed_authorization_header(value: str) -> None:
    with pytest.raises(Refused, match="Bearer"):
        authenticate(False, "127.0.0.1", [*LOCAL, ("Authorization", value)], verify)


def test_disabled_refuses_two_authorization_headers() -> None:
    headers = [*bearer("ordinary-token"), ("Authorization", "Bearer reserved-token")]
    with pytest.raises(Refused, match="one Authorization"):
        authenticate(False, "127.0.0.1", headers, verify)


# Disabled, but the request did not come from this machine.


@pytest.mark.parametrize(
    "peer", [None, "10.0.0.7", "192.168.1.5", "203.0.113.7", "::ffff:10.0.0.7"]
)
def test_disabled_refuses_a_peer_off_this_machine(peer: str | None) -> None:
    with pytest.raises(Refused, match="this machine"):
        authenticate(False, peer, LOCAL, verify)


@pytest.mark.parametrize(
    "extra",
    [
        ("Forwarded", "for=127.0.0.1"),
        ("X-Forwarded-For", "127.0.0.1"),
        ("X-Forwarded-For", "203.0.113.7"),
        ("X-Forwarded-Proto", "https"),
        ("X-Real-IP", "203.0.113.7"),
        ("X-Forwarded-Host", "app.example.com"),
        ("X-Forwarded-Host", "192.168.1.5:3000"),
        ("X-Forwarded-Host", "localhost, app.example.com"),
    ],
)
def test_disabled_refuses_a_request_a_proxy_forwarded(extra: tuple[str, str]) -> None:
    with pytest.raises(Refused, match="this machine"):
        authenticate(False, "127.0.0.1", [*LOCAL, extra], verify)


@pytest.mark.parametrize(
    "headers",
    [
        [],
        [("Host", "rebound.example.com:8000")],
        [("Host", "localhost:8000"), ("Host", "rebound.example.com")],
        [("Host", "localhost@rebound.example.com")],
        [("Host", "::1")],
    ],
)
def test_disabled_refuses_a_host_header_that_is_not_loopback(
    headers: list[tuple[str, str]],
) -> None:
    with pytest.raises(Refused, match="this machine"):
        authenticate(False, "127.0.0.1", headers, verify)


@pytest.mark.parametrize(
    "extra",
    [
        ("Origin", "https://site.example.com"),
        ("Origin", "null"),
        ("Origin", "file://"),
        ("Sec-Fetch-Site", "cross-site"),
    ],
)
def test_disabled_refuses_a_page_on_another_site(extra: tuple[str, str]) -> None:
    with pytest.raises(Refused, match="this machine"):
        authenticate(False, "127.0.0.1", [*LOCAL, extra], verify)


# Enabled: a credential is required, and none may name the reserved identity.


def test_enabled_refuses_a_request_with_no_credential() -> None:
    with pytest.raises(Refused, match="sign in required"):
        authenticate(True, "127.0.0.1", LOCAL, verify)


def test_enabled_accepts_an_ordinary_credential_from_anywhere() -> None:
    headers = [("Host", "app.example.com"), ("Authorization", "Bearer ordinary-token")]
    assert authenticate(True, "203.0.113.7", headers, verify) == Principal(ORDINARY)


@pytest.mark.parametrize("token", ["reserved-token", "expired-token"])
def test_enabled_refuses_the_reserved_identity_and_invalid_credentials(token: str) -> None:
    with pytest.raises(Refused):
        authenticate(True, "127.0.0.1", bearer(token), verify)


# The listener rule: FALSE starts only on loopback.


@pytest.mark.parametrize("host", ["localhost", "LOCALHOST", "127.0.0.1", "::1"])
@pytest.mark.parametrize("public_url", [None, "", "http://localhost:8080", "http://[::1]:8080/app"])
def test_disabled_starts_on_a_loopback_listener(host: str, public_url: str | None) -> None:
    check_listener(False, host, public_url)


@pytest.mark.parametrize(
    "host", ["0.0.0.0", "::", "192.168.1.5", "api", "app.example.com", "localhost.", ""]
)
def test_disabled_refuses_to_start_on_a_wider_listener(host: str) -> None:
    with pytest.raises(AuthSettingError, match="loopback listener"):
        check_listener(False, host, None)


@pytest.mark.parametrize(
    "public_url",
    [
        "https://app.example.com",
        "http://192.168.1.5",
        "http://localhost@app.example.com",
        "localhost",
    ],
)
def test_disabled_refuses_to_start_with_a_public_origin(public_url: str) -> None:
    with pytest.raises(AuthSettingError, match="PUBLIC_URL"):
        check_listener(False, "127.0.0.1", public_url)


def test_enabled_starts_anywhere() -> None:
    check_listener(True, "0.0.0.0", "https://app.example.com")
