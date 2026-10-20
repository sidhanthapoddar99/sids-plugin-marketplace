// common: config loader (config.rs — root .env file skip-if-set, config.yaml + config.local.yaml, ${VAR}, ENGINE__ overrides),
// error types, shared domain types. Every other crate depends on this one; it depends on nothing internal.
// auth_mode.rs reads AUTH_ENABLED and refuses FALSE on a non-loopback listener; the loader calls it.

pub mod auth_mode;
