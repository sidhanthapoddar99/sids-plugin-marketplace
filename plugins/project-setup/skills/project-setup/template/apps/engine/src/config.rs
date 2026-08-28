// The one config loader. dotenvy::from_path(ROOT/.env) without override → read config.yaml →
// substitute ${VAR} from std::env, Err on missing → deserialize into `Settings`.
