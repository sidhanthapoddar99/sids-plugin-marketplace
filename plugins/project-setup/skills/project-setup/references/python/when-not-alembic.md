# When NOT to use Alembic

Alembic is the default, but it's not universal. Cases where another approach is better.

## When raw SQL files only (no Alembic)

Projects where Python isn't the primary language and the migration runner is something else:

- **Rust-first**: use `sqlx migrate` directly with `*.sql` files
- **Go-first**: use `golang-migrate/migrate` or `goose`
- **Schema served by another tool**: Prisma (TS), Diesel (Rust), Ent (Go)

If Python is just one consumer among others, defer to the language with the strongest migration ecosystem.

## When migrations are managed by the database service itself

Some setups use Postgres extensions or operators for schema management:

- **Hasura** — schema lives in the Hasura metadata
- **Supabase** — schema migrations via Supabase CLI
- **Cloud-managed Postgres with schema-as-code** — e.g. via Atlas, sqitch

In these, Alembic would be duplicative and lose features.

## When the project is so simple no migration tool is justified

- Single-table prototype
- Read-only analytics DB managed elsewhere
- Schema defined as part of test fixtures

For prototypes, a single `init.sql` mounted as `/docker-entrypoint-initdb.d/01_schema.sql` is fine. Migrate to Alembic when the schema starts changing.

## When NoSQL / schemaless

- MongoDB — no DDL; schema lives in application code (with validators)
- Redis — no schema beyond key conventions
- Neo4j / Kuzu — Cypher schema operations don't fit Alembic
- Elasticsearch — index mappings managed via API calls

Each has its own conventions; don't force Alembic in.

## When using a non-relational ORM-managed store

- DynamoDB — no schema; just table creation via Terraform / CDK
- BigQuery / Snowflake — DDL via the cloud console or dbt

## Decision flow

```
Is the project Python-only with a relational DB?
├── Yes → Alembic (default)
├── No, multi-language → Alembic with raw-SQL shim pattern (see alembic-with-raw-sql.md)
└── No, language isn't Python → use that language's native migration tool
    │
    ├── Rust → sqlx migrate
    ├── Go → golang-migrate or goose
    ├── TS → Prisma / Drizzle / Kysely
    └── Multiple, no obvious owner → raw SQL files + simple runner script
```

## Hand-rolled migrations (the atheneum-style alternative, not recommended without reason)

Atheneum **briefly** considered hand-rolled migrations before switching to Alembic + raw SQL. Hand-rolled means:

- A `migrations/` folder with sequentially numbered SQL files
- A `schema_migrations` table tracking applied versions
- A shell or Python script that applies pending migrations

Pros: zero deps. Cons: reinvents Alembic poorly. **Only justified** for projects where adding Alembic is overkill (e.g. a tiny utility that owns one table). For anything growing, use Alembic.

## When migrations are append-only (event sourcing)

Some architectures don't migrate schema at all — they migrate **data** as events. Schema is wide and append-only. Out of scope for this guide.

## Anti-patterns

- Avoiding Alembic because "it's too complex" → adopt earlier rather than later; retrofitting is painful
- Mixing Alembic with hand-rolled migrations in the same DB — pick one
- Letting `Base.metadata.create_all()` run in production — never; migrations explicit
- Migrating away from Alembic without a clear successor in place
