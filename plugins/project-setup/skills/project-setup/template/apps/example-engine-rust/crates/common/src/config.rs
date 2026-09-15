// The one config loader. Precedence: process env > config.local.yaml > config.yaml.
// find repo root (walk up to `ctl`); load root .env skip-if-set, then resolve ${VAR} references
// with the ctl loader's semantics (forward references, unset/cycle failure; no shell evaluation)
// → read config.yaml, deep-merge config.local.yaml (arrays replace) → substitute ${VAR}, Err on a missing one
// → apply `ENGINE__<SECTION>__<KEY>` env overrides → deserialize into `Settings`.
