# engine — Rust, Axum

Data plane: heavy reads, graph queries against Neo4j, streaming. Reads Postgres, never writes it.
Validates the same `JWT_SIGNING_KEY` as api; issues nothing.

Run from here: `cargo run`. Reads the root `.env.secrets` / `.env.proxy` (skip-if-set) and `config.yaml`. Run through `ctl dev engine` so they are loaded. Test: `cargo test`.
