// The one config loader. Precedence: process env > config.local.yaml > config.yaml.
// find repo root (walk up to `ctl`) → dotenvy::from_path(ROOT/.env) without override (no-op under docker)
// → read config.yaml, deep-merge config.local.yaml if present → substitute ${VAR} from std::env,
// Err on a missing one → deserialize into `Settings`.
