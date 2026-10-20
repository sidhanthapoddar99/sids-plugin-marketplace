// The binary. Builds Settings via common::load(), opens pools into AppState, mounts one thin handler module per domain
// (workspaces.rs, blocks.rs …) under settings.server.prefix, plus /health and /ready. Handlers call data + auth; no SQL here.
// common::load() refuses AUTH_ENABLED=FALSE on a non-loopback listener, so the binary exits before it binds. It serves
// with into_make_service_with_connect_info::<SocketAddr>(), because the auth extractor checks the peer address, and
// logs one warning at startup under FALSE: requests without a credential act as the reserved user.
