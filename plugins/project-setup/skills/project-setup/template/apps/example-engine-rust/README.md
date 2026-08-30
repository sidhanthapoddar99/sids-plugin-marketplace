# engine — Rust, Axum

Data plane: heavy reads, graph queries against Neo4j, streaming. Reads Postgres, never writes it.
Validates the same `JWT_SIGNING_KEY` as api; issues nothing.

Run from here: `cargo run`. Reads the root `.env.secrets` / `.env.proxy` (skip-if-set) and `config.yaml`. Run through `ctl dev engine` so they are loaded. Test: `cargo test`.

## Layout

A cargo workspace, one crate per layer:

```
crates/
├── common/   config loader, errors, shared types — depends on nothing internal
├── data/     every query, one module per domain; sqlx offline metadata in .sqlx/
├── auth/     JWT validation, ACL, middleware
└── api/      the binary: AppState, thin handlers by domain, /health /ready
```

`api → auth, data → common`. A layer becomes a crate because it is reused by more than one binary or compiled apart; a small service is one crate with the same modules.
