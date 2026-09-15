# Working rules

- `ctl` is the only way to run, build, migrate or test. Never call docker, alembic, uv or bun directly for those.
- Keep settings in the ignored root `.env`, grouped by kind with two-line hash headers. Read `.env.template` for the contract; the filled file holds live secrets.
- Schema changes go through `apps/database/postgres/migrations/`. Never edit a live schema.
- An app never imports from another app. Shared code is a package under `apps/packages/`.
- Documentation points at code. A code comment never names a doc page, plan, issue or skill file. `README.md`, `AGENTS.md` and `memory/` are the only exceptions.
- A frontend has no app-local env file. Its dev server inherits the root environment; expose only selected public constants to browser code, because bundles are public.
