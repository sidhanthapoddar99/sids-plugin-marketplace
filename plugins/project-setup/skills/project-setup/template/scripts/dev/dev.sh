#!/usr/bin/env bash
# ctl dev [app...] — engines in docker, apps on the host with reload.
# compose dev up -d, wait for healthy, then start each app in its own process:
#   api    uv run --directory apps/api uvicorn app.main:app --reload --port $API_PORT
#   engine cargo watch -C apps/engine -x run
#   web    bun --cwd apps/web dev
#   site   bun --cwd apps/site dev
# Trap SIGINT: stop the apps, leave the engines running.
