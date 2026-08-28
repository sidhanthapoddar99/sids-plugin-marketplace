# Multi-stage. uv installs into a venv in the builder; runtime image copies the venv, runs non-root.
# No secrets at build time. Everything arrives at runtime through env_file / environment.
# FROM python:<version>-slim AS builder  → uv sync --frozen --no-dev
# FROM python:<version>-slim             → COPY --from=builder /app/.venv; USER app; CMD uvicorn app.main:app
