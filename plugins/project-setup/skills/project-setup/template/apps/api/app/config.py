# The one config loader. Nothing else in the app reads os.environ or a file.
# 1. load_dotenv(ROOT/.env, override=False)
# 2. yaml.safe_load(config.yaml)
# 3. walk the tree; replace every ${VAR} with os.environ[VAR]; raise on a missing one, naming the key
# 4. validate into a pydantic Settings model; export `settings`
