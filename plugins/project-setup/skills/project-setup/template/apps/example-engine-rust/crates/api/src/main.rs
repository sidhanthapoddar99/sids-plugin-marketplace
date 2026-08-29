// The binary. Builds Settings via common::load(), opens pools into AppState, mounts one thin handler module per domain
// (workspaces.rs, blocks.rs …) under settings.server.prefix, plus /health and /ready. Handlers call data + auth; no SQL here.
