# Multi-stage. uv installs into a venv in the builder; runtime image copies the venv, runs non-root.
# No secrets at build time. Everything arrives at runtime through compose `environment:`.
# FROM python:3.13-slim AS builder  → uv sync --frozen --no-dev
# FROM python:3.13-slim             → COPY --from=builder /app/.venv; USER app; CMD uvicorn app.main:app
