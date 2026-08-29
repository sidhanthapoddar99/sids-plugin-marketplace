// The one config loader. Precedence: process env > config.local.yaml > config.yaml.
// find repo root (walk up to `ctl`) → dotenvy::from_path for .env.secrets, .env.data, .env.proxy, without override
// → read config.yaml, deep-merge config.local.yaml (arrays replace) → substitute ${VAR}, Err on a missing one
// → apply `ENGINE__<SECTION>__<KEY>` env overrides → deserialize into `Settings`.
