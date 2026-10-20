//! Who a request acts as, including development sign-in.
//!
//! AUTH_ENABLED=TRUE: every request needs a credential, and no credential may name the reserved
//! identity. AUTH_ENABLED=FALSE: a request with no credential acts as the reserved `default` user
//! that the migration V3__development_identity.sql creates, but only a request made on this
//! machine. In both modes a credential, valid or not, is verified and never falls back to
//! `default`, so an expired token fails instead of quietly becoming someone else.
//!
//! No framework type appears here, so a unit test proves the rules without a server. The axum
//! extractor every handler takes feeds `authenticate` one request: the peer from
//! `ConnectInfo<SocketAddr>` (serve with `into_make_service_with_connect_info`), the header pairs
//! as `(name.as_str(), value.as_bytes())`, and the JWT check. It answers `Refused` with 401.

use common::auth_mode::{authority_host, is_loopback_host, is_loopback_ip, url_host};
use std::net::IpAddr;

/// The fixed id from V3__development_identity.sql. The api's core/auth.py holds the same value.
pub const RESERVED_USER_ID: &str = "00000000-0000-4000-8000-000000000001";

/// The user a request acts as.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Principal {
    pub user_id: String,
    /// True only for the reserved identity, so a `me` response can tell the UI to show it.
    pub development: bool,
}

/// The request gets no principal. The extractor answers 401 with this message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refused(pub &'static str);

/// True when `user_id` is the reserved id, in any case and with or without hyphens.
pub fn is_reserved(user_id: &str) -> bool {
    let canonical = |id: &str| {
        id.chars()
            .filter(|c| *c != '-')
            .collect::<String>()
            .to_ascii_lowercase()
    };
    canonical(user_id) == canonical(RESERVED_USER_ID)
}

/// The reserved identity has no credential, so any credential that names it is refused.
pub fn refuse_reserved(user_id: &str) -> Result<(), Refused> {
    if is_reserved(user_id) {
        return Err(Refused(
            "the reserved development identity cannot sign in or hold a credential",
        ));
    }
    Ok(())
}

/// The principal for one request. `verify` takes a bearer token and returns its user id.
pub fn authenticate<F>(
    auth_enabled: bool,
    peer: Option<IpAddr>,
    headers: &[(&str, &[u8])],
    verify: F,
) -> Result<Principal, Refused>
where
    F: FnOnce(&str) -> Result<String, Refused>,
{
    let mut credentials = headers
        .iter()
        .filter(|(name, _)| name.eq_ignore_ascii_case("authorization"));
    if let Some((_, value)) = credentials.next() {
        let token = std::str::from_utf8(value)
            .ok()
            .and_then(|v| v.split_once(' '))
            .filter(|(scheme, token)| scheme.eq_ignore_ascii_case("bearer") && !token.is_empty())
            .map(|(_, token)| token);
        let token = match (token, credentials.next()) {
            (Some(token), None) => token,
            _ => return Err(Refused("send one Authorization: Bearer <token> header")),
        };
        let user_id = verify(token)?;
        refuse_reserved(&user_id)?;
        return Ok(Principal {
            user_id,
            development: false,
        });
    }
    if auth_enabled {
        return Err(Refused("sign in required"));
    }
    if !request_is_local(peer, headers) {
        return Err(Refused(
            "development sign-in serves only requests made on this machine",
        ));
    }
    Ok(Principal {
        user_id: RESERVED_USER_ID.into(),
        development: true,
    })
}

/// True when nothing says the request came from off this machine or from a web page elsewhere.
///
/// The peer address catches a server bound wider than the settings say. The Host header catches
/// DNS rebinding. Forwarding headers catch a reverse proxy. Origin and Sec-Fetch-Site catch a
/// page on another site that the developer's browser is visiting.
pub fn request_is_local(peer: Option<IpAddr>, headers: &[(&str, &[u8])]) -> bool {
    let peer_local = peer.is_some_and(is_loopback_ip);
    let has_host = headers
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("host"));
    peer_local
        && has_host
        && headers
            .iter()
            .all(|(name, value)| header_is_local(name, value))
}

fn header_is_local(name: &str, value: &[u8]) -> bool {
    let name = name.to_ascii_lowercase();
    let Ok(value) = std::str::from_utf8(value) else {
        return false;
    };
    match name.as_str() {
        // A dev server's proxy may add X-Forwarded-Host (Next.js rewrites do).
        "host" | "x-forwarded-host" => authority_host(value).is_some_and(is_loopback_host),
        "origin" => url_host(value).is_some_and(is_loopback_host),
        "sec-fetch-site" => !value.eq_ignore_ascii_case("cross-site"),
        // Any other forwarding header means a proxy relayed the request from somewhere else.
        _ => !(name == "forwarded" || name == "x-real-ip" || name.starts_with("x-forwarded-")),
    }
}

#[cfg(test)]
mod tests;
