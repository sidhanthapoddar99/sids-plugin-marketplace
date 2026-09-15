# The one config loader. Nothing else in the app reads os.environ or a file.
# Precedence: process env > config.local.yaml > config.yaml.
# 1. find the repo root (walk up until a dir holds `ctl`); parse raw .env KEY=value lines
#    with the ctl parser's semantics: unquoted values, CRLF and trailing whitespace comments,
#    skip-if-set. Resolve ${VAR} only after all keys are loaded; fail on unset references or cycles.
#    Do not use dotenv's eager interpolation: it can erase a forward or missing reference.
#    Under docker the file is absent: compose already set the declared environment keys.
# 2. yaml.safe_load(config.yaml); deep-merge config.local.yaml over it if present (gitignored).
# 3. walk the tree; replace every ${VAR} with os.environ[VAR]; raise on a missing one, naming the key.
# 4. apply the nested override channel: an env var `API__<SECTION>__<KEY>` (pydantic env_nested_delimiter="__",
#    env_prefix="API__") overrides that one literal. This is how a container or CI tweaks pool_size without a file.
# 5. validate into a pydantic Settings model; export `settings`.
