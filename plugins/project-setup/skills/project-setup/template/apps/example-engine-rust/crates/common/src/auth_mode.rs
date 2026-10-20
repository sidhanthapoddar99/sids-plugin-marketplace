//! AUTH_ENABLED, the sign-in switch, and the loopback rule that keeps FALSE on this machine.
//!
//! The loader in config.rs calls `parse_auth_enabled` on the `auth.enabled` text, then
//! `check_listener` with the server host and the process's PUBLIC_URL, so FALSE on a
//! non-loopback listener stops the start. The host helpers serve the auth crate's request check.

use std::fmt;
use std::net::IpAddr;

/// AUTH_ENABLED is not TRUE or FALSE, or it is FALSE where FALSE is unsafe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthSettingError(pub String);

impl fmt::Display for AuthSettingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for AuthSettingError {}

/// TRUE or FALSE in any case. Any other text fails, because a guessed mode is a wrong mode.
pub fn parse_auth_enabled(raw: &str) -> Result<bool, AuthSettingError> {
    if raw.eq_ignore_ascii_case("TRUE") {
        Ok(true)
    } else if raw.eq_ignore_ascii_case("FALSE") {
        Ok(false)
    } else {
        Err(AuthSettingError(format!(
            "AUTH_ENABLED must be TRUE or FALSE, not {raw:?}"
        )))
    }
}

/// Refuse to start with FALSE unless the listener and any public origin are loopback.
pub fn check_listener(
    auth_enabled: bool,
    host: &str,
    public_url: Option<&str>,
) -> Result<(), AuthSettingError> {
    if auth_enabled {
        return Ok(());
    }
    if !is_loopback_host(host) {
        return Err(AuthSettingError(format!(
            "AUTH_ENABLED=FALSE needs a loopback listener, and this backend binds {host:?}. \
             Set AUTH_ENABLED=TRUE, or bind 127.0.0.1."
        )));
    }
    match public_url {
        Some(url) if !url.is_empty() && !url_host(url).is_some_and(is_loopback_host) => Err(AuthSettingError(
            "AUTH_ENABLED=FALSE refuses a public origin, and PUBLIC_URL names a non-loopback host. \
             Set AUTH_ENABLED=TRUE, or comment out PUBLIC_URL."
                .into(),
        )),
        _ => Ok(()),
    }
}

/// `localhost`, 127.0.0.0/8 or ::1. A name that only resolves to loopback does not count.
pub fn is_loopback_host(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost") || host.parse::<IpAddr>().is_ok_and(is_loopback_ip)
}

/// 127.0.0.0/8, ::1, or an IPv4-mapped IPv6 address of 127.0.0.0/8.
pub fn is_loopback_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => v4.is_loopback(),
        IpAddr::V6(v6) => {
            v6.is_loopback() || v6.to_ipv4_mapped().is_some_and(|v4| v4.is_loopback())
        }
    }
}

/// The host of `host`, `host:port` or `[v6]:port`. None when the text is anything else.
pub fn authority_host(authority: &str) -> Option<&str> {
    if authority.is_empty() || authority.contains(['@', '/', '?', '#', '\\', ' ', '\t', ',']) {
        return None;
    }
    let (host, rest) = match authority.strip_prefix('[') {
        Some(bracketed) => bracketed.split_once(']')?,
        None => authority
            .find(':')
            .map_or((authority, ""), |i| authority.split_at(i)),
    };
    let port_ok = rest.is_empty()
        || rest
            .strip_prefix(':')
            .is_some_and(|port| !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit()));
    (port_ok && !host.is_empty()).then_some(host)
}

/// The host of an http(s) URL or Origin header value. None when it is not one.
pub fn url_host(url: &str) -> Option<&str> {
    let (scheme, rest) = url.split_once("://")?;
    if !(scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https")) {
        return None;
    }
    authority_host(rest.split('/').next().unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_switch_reads_true_or_false_in_any_case() {
        for (raw, enabled) in [
            ("TRUE", true),
            ("true", true),
            ("FALSE", false),
            ("False", false),
        ] {
            assert_eq!(parse_auth_enabled(raw), Ok(enabled), "{raw}");
        }
    }

    #[test]
    fn any_other_switch_value_fails() {
        for raw in ["", "1", "0", "yes", "off", " TRUE", "FALSE "] {
            let error = parse_auth_enabled(raw).unwrap_err();
            assert!(
                error.0.contains("AUTH_ENABLED must be TRUE or FALSE"),
                "{raw:?}: {error}"
            );
        }
    }

    #[test]
    fn disabled_starts_on_a_loopback_listener() {
        for host in ["localhost", "LOCALHOST", "127.0.0.1", "::1"] {
            for public_url in [
                None,
                Some(""),
                Some("http://localhost:8080"),
                Some("http://[::1]:8080/app"),
            ] {
                assert_eq!(
                    check_listener(false, host, public_url),
                    Ok(()),
                    "{host} {public_url:?}"
                );
            }
        }
    }

    #[test]
    fn disabled_refuses_to_start_on_a_wider_listener() {
        for host in [
            "0.0.0.0",
            "::",
            "192.168.1.5",
            "engine",
            "app.example.com",
            "localhost.",
            "",
        ] {
            let error = check_listener(false, host, None).unwrap_err();
            assert!(error.0.contains("loopback listener"), "{host:?}: {error}");
        }
    }

    #[test]
    fn disabled_refuses_to_start_with_a_public_origin() {
        for url in [
            "https://app.example.com",
            "http://192.168.1.5",
            "http://localhost@app.example.com",
            "localhost",
        ] {
            let error = check_listener(false, "127.0.0.1", Some(url)).unwrap_err();
            assert!(error.0.contains("PUBLIC_URL"), "{url}: {error}");
        }
    }

    #[test]
    fn enabled_starts_anywhere() {
        assert_eq!(
            check_listener(true, "0.0.0.0", Some("https://app.example.com")),
            Ok(())
        );
    }

    #[test]
    fn authority_host_accepts_only_a_host_and_a_port() {
        assert_eq!(authority_host("localhost:8000"), Some("localhost"));
        assert_eq!(authority_host("[::1]:8000"), Some("::1"));
        assert_eq!(authority_host("127.0.0.1"), Some("127.0.0.1"));
        for bad in [
            "",
            "::1",
            "localhost:",
            "localhost:80a",
            "a@localhost",
            "localhost/x",
            "localhost, x",
            "[::1",
        ] {
            assert_eq!(authority_host(bad), None, "{bad:?}");
        }
    }
}
