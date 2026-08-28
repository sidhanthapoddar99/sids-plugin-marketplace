# Working rules

- `ctl` is the only way to run, build, migrate or test. Never call docker, alembic, uv or bun directly for those.
- Secrets live in `.env`. Read `.env.example` to learn the contract. Never read `.env`.
- Schema changes go through `apps/database/migrations/`. Never edit a live schema.
- An app never imports from another app. Shared code is a package under `apps/packages/`.
- Frontend `.env` holds public values only.
