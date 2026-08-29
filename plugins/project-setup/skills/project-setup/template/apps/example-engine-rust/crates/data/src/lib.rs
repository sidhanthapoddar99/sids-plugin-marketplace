// data: every Postgres and Neo4j query, one module per domain (users.rs, blocks.rs …). sqlx::query! for compile-time
// checks; .sqlx/ committed; `ctl migrate` then `ctl sqlx-prepare` after a schema change. No rules, no HTTP.
