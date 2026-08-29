// The one config loader. Precedence: process env > config.local.yaml > config.yaml.
// find repo root (walk up to `ctl`) → dotenvy::from_path(ROOT/<f>) without override for .env.secrets,
// .env.data, .env.proxy in that order (no-op under docker)
// → read config.yaml, deep-merge config.local.yaml if present → substitute ${VAR} from std::env,
// Err on a missing one → apply `ENGINE__<SECTION>__<KEY>` env overrides on literals → deserialize into `Settings`.
