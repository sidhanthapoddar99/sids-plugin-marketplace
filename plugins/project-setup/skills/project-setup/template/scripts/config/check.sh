#!/usr/bin/env bash
# ctl check — conformance floor. Exit non-zero on the first failure.
# - every key in config.yaml ${VAR} exists in .env.example
# - every key in .env.example is documented (comment on the line)
# - no package.json, bun.lock at root or apps/
# - no ports: in compose.base.yaml
# - docker compose config validates for every ctl up combination
# - CLAUDE.md is exactly "@AGENTS.md"
