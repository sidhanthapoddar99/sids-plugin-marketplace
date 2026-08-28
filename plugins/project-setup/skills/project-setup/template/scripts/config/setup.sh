#!/usr/bin/env bash
# ctl setup — first run on a clone.
# 1. cp .env.example .env if .env is missing. Never overwrite.
# 2. fill every blank *_KEY with `openssl rand -hex 32`, every blank *_PASSWORD with base64 24.
# 3. mkdir -p data/{postgres,redis,neo4j,test_build} owned by the current user.
# 4. per-frontend: cp apps/<fe>/.env.example apps/<fe>/.env if missing.
# 5. mise install, uv sync per python app, bun install per js app.
