//! Development sign-in in both directions, and the request checks that keep FALSE local.

use super::*;

const ORDINARY: &str = "6f1c2e9a-3b7d-4c55-9e2a-0d4b8f7a1c33";
const LOCAL: (&str, &[u8]) = ("host", b"localhost:8080");

fn verify(token: &str) -> Result<String, Refused> {
    match token {
        "ordinary-token" => Ok(ORDINARY.into()),
        "reserved-token" => Ok(RESERVED_USER_ID.into()),
        "reserved-token-no-hyphens" => Ok("00000000000040008000000000000001".into()),
        _ => Err(Refused("invalid token")),
    }
}

fn loopback() -> Option<IpAddr> {
    Some("127.0.0.1".parse().unwrap())
}

fn run(
    enabled: bool,
    peer: Option<IpAddr>,
    headers: &[(&str, &[u8])],
) -> Result<Principal, Refused> {
    authenticate(enabled, peer, headers, verify)
}

fn reserved() -> Principal {
    Principal {
        user_id: RESERVED_USER_ID.into(),
        development: true,
    }
}

fn ordinary() -> Principal {
    Principal {
        user_id: ORDINARY.into(),
        development: false,
    }
}

const NOT_LOCAL: Refused = Refused("development sign-in serves only requests made on this machine");

// Disabled: a local request with no credential acts as the reserved identity.

#[test]
fn disabled_gives_a_local_request_the_reserved_identity() {
    for peer in ["127.0.0.1", "127.8.9.10", "::1", "::ffff:127.0.0.1"] {
        assert_eq!(
            run(false, Some(peer.parse().unwrap()), &[LOCAL]),
            Ok(reserved()),
            "{peer}"
        );
    }
}

#[test]
fn disabled_accepts_a_local_browser_or_dev_server_proxy() {
    let extras: [(&str, &[u8]); 4] = [
        ("origin", b"http://localhost:5173"),
        ("sec-fetch-site", b"same-site"),
        ("x-forwarded-host", b"localhost:3000"),
        ("X-Forwarded-Host", b"127.0.0.1"),
    ];
    for extra in extras {
        assert_eq!(
            run(false, loopback(), &[LOCAL, extra]),
            Ok(reserved()),
            "{extra:?}"
        );
    }
}

#[test]
fn disabled_still_verifies_a_credential_and_acts_as_its_owner() {
    let headers = [
        LOCAL,
        ("authorization", b"Bearer ordinary-token".as_slice()),
    ];
    assert_eq!(run(false, loopback(), &headers), Ok(ordinary()));
}

#[test]
fn disabled_never_turns_a_bad_credential_into_the_reserved_identity() {
    for value in [
        b"Bearer expired-token".as_slice(),
        b"Bearer reserved-token",
        b"Bearer reserved-token-no-hyphens",
        b"Basic abc",
        b"Bearer",
        b"Bearer ",
        b"token",
        b"Bearer \xff",
    ] {
        let result = run(false, loopback(), &[LOCAL, ("authorization", value)]);
        assert!(result.is_err(), "{value:?} gave {result:?}");
    }
}

#[test]
fn disabled_refuses_two_authorization_headers() {
    let headers = [
        LOCAL,
        ("authorization", b"Bearer ordinary-token".as_slice()),
        ("authorization", b"Bearer x"),
    ];
    assert_eq!(
        run(false, loopback(), &headers),
        Err(Refused("send one Authorization: Bearer <token> header"))
    );
}

// Disabled, but the request did not come from this machine.

#[test]
fn disabled_refuses_a_peer_off_this_machine() {
    assert_eq!(run(false, None, &[LOCAL]), Err(NOT_LOCAL));
    for peer in ["10.0.0.7", "192.168.1.5", "203.0.113.7", "::ffff:10.0.0.7"] {
        assert_eq!(
            run(false, Some(peer.parse().unwrap()), &[LOCAL]),
            Err(NOT_LOCAL),
            "{peer}"
        );
    }
}

#[test]
fn disabled_refuses_a_request_a_proxy_forwarded() {
    let extras: [(&str, &[u8]); 8] = [
        ("forwarded", b"for=127.0.0.1"),
        ("x-forwarded-for", b"127.0.0.1"),
        ("x-forwarded-for", b"203.0.113.7"),
        ("x-forwarded-proto", b"https"),
        ("x-real-ip", b"203.0.113.7"),
        ("x-forwarded-host", b"app.example.com"),
        ("x-forwarded-host", b"192.168.1.5:3000"),
        ("x-forwarded-host", b"localhost, app.example.com"),
    ];
    for extra in extras {
        assert_eq!(
            run(false, loopback(), &[LOCAL, extra]),
            Err(NOT_LOCAL),
            "{extra:?}"
        );
    }
}

#[test]
fn disabled_refuses_a_host_header_that_is_not_loopback() {
    let cases: [&[(&str, &[u8])]; 6] = [
        &[],
        &[("host", b"rebound.example.com:8080")],
        &[LOCAL, ("host", b"rebound.example.com")],
        &[("host", b"localhost@rebound.example.com")],
        &[("host", b"::1")],
        &[("host", b"\xfflocalhost")],
    ];
    for headers in cases {
        assert_eq!(
            run(false, loopback(), headers),
            Err(NOT_LOCAL),
            "{headers:?}"
        );
    }
}

#[test]
fn disabled_refuses_a_page_on_another_site() {
    let extras: [(&str, &[u8]); 4] = [
        ("origin", b"https://site.example.com"),
        ("origin", b"null"),
        ("origin", b"file://"),
        ("sec-fetch-site", b"cross-site"),
    ];
    for extra in extras {
        assert_eq!(
            run(false, loopback(), &[LOCAL, extra]),
            Err(NOT_LOCAL),
            "{extra:?}"
        );
    }
}

// Enabled: a credential is required, and none may name the reserved identity.

#[test]
fn enabled_refuses_a_request_with_no_credential() {
    assert_eq!(
        run(true, loopback(), &[LOCAL]),
        Err(Refused("sign in required"))
    );
}

#[test]
fn enabled_accepts_an_ordinary_credential_from_anywhere() {
    let headers = [
        ("host", b"app.example.com".as_slice()),
        ("authorization", b"Bearer ordinary-token"),
    ];
    assert_eq!(
        run(true, Some("203.0.113.7".parse().unwrap()), &headers),
        Ok(ordinary())
    );
}

#[test]
fn enabled_refuses_the_reserved_identity_and_invalid_credentials() {
    for value in [
        b"Bearer reserved-token".as_slice(),
        b"Bearer reserved-token-no-hyphens",
        b"Bearer expired-token",
    ] {
        assert!(
            run(true, loopback(), &[LOCAL, ("authorization", value)]).is_err(),
            "{value:?}"
        );
    }
}
