# The one config loader. Nothing else in the app reads os.environ or a file.
# Precedence: process env > config.local.yaml > config.yaml.
# 1. find the repo root (walk up until a dir holds `ctl`); load_dotenv(ROOT/<f>, override=False) for
#    .env.secrets, .env.data, .env.proxy, in that order. Under docker none of them exist: compose set the
#    environment, so this step is a no-op.
# 2. yaml.safe_load(config.yaml); deep-merge config.local.yaml over it if present (gitignored).
# 3. walk the tree; replace every ${VAR} with os.environ[VAR]; raise on a missing one, naming the key.
# 4. validate into a pydantic Settings model; export `settings`.
