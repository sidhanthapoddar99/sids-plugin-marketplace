#!/usr/bin/env bash
# ctl migrate — apply migrations. The only path that touches schema.
# postgres: uv run --directory apps/database/postgres alembic upgrade head
# neo4j:    cypher-shell < apps/database/neo4j/init.cypher (idempotent: IF NOT EXISTS)
# Runs on the host against .env values, or inside the api container under `ctl up`.
