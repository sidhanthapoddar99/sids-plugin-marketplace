# Database ownership

Relational schema changes use Flyway SQL migrations regardless of application language.
The Flyway image is pinned in the migration Dockerfile; no host CLI is needed.

| Folder | Holds | Applied by |
|---|---|---|
| `postgres/` | `flyway.conf`, versioned SQL in `migrations/`, migration `Dockerfile` | `ctl db migrate` and Compose's `migrate` one-shot |
| `neo4j/` | `init.cypher` constraints and indexes | `neo4j-init` one-shot |
| `redis/` | `redis.conf` | mounted by Compose |

`ctl db migrate new "add_projects"` creates one SQL file without connecting to a database.
Write the SQL, then apply it with `ctl db migrate`. Use `status` to list migrations or
`check` to verify currency. The runner connects to PostgreSQL inside the Compose network.
Production applications wait for the migration service; they do not migrate at startup.
Flyway records versions and checksums in PostgreSQL. Correct applied SQL with a new
migration; forward-only changes avoid pretending that every data change can be undone.
Backups, restores and explicitly authorized resets are separate operations.
