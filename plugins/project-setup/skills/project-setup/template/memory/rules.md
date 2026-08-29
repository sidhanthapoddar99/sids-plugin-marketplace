# Working rules

- `ctl` is the only way to run, build, migrate or test. Never call docker, alembic, uv or bun directly for those.
- Secrets live in `.env.secrets`. Paths in `.env.data`. Hosts, ports and prefixes in `.env.proxy`. Read the `.env.*.template` files to learn the contract. Never read the filled files.
- Schema changes go through `apps/database/postgres/migrations/`. Never edit a live schema.
- An app never imports from another app. Shared code is a package under `apps/packages/`.
- A frontend has no `.env`. Its prefix is a build arg from `.env.proxy`; everything in a bundle is public.
