# The migrate one-shot (compose.db.yaml `migrate`). Runs inside the compose network, so no engine
# port is published for it. `ctl db migrate` runs it with `docker compose run --rm --no-deps migrate`;
# the apps wait on it with condition: service_completed_successfully.
# FROM python:<version>-slim  → uv sync --frozen --no-dev; WORKDIR /work (bind-mounted from this folder)
# CMD ["alembic", "upgrade", "head"]
