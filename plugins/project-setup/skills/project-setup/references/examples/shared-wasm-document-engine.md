# Example: shared WASM document engine

An optional design for collaborative raster/vector editors and other typed documents.
This is a reference example, not a required stack or an extension installed by the
base template. Ordinary CRUD applications usually benefit from a simpler design.

## Components and ownership

| Component | Responsibility |
|---|---|
| User frontend: Vite and React | Navigation, editor UI, browser-worker lifecycle and local previews |
| Separate admin frontend: Vite and React | Operator screens; backend authorization still enforces access |
| Python API | Identity, project permissions, catalogs, asset ingestion and external API proxying |
| Rust document service | Authorized WebSocket sessions, operation ordering, Wasmtime execution and durable recovery |
| One package per document type | Rust model, operations, queries, checkpoint codecs, saved-format migrations and editor UI |
| Shared Rust synchronization core | Confirmed state, pending predictions, acknowledgements and reconciliation |
| Optional agent runtime | Tool calls through the same authorized document command path used by people |
| PostgreSQL and S3-compatible storage | Metadata and accepted operation records in PostgreSQL; immutable assets and checkpoints in object storage |

The browser and server compile the same document core for their respective WASM
hosts. The browser runs it in a Web Worker; the server runs it in Wasmtime. The
service remains generic rather than accumulating branches for each document type.
A thin TypeScript adapter connects worker projections to the UI. A representative
package contains:

```text
apps/packages/
  document-abi/                 # Shared host interface and replay-input contract
  document-sync-engine/         # Shared reconciliation logic
  documents/vector-design/
    core/src/
      state/                    # Document model
      operations/               # Validated atomic edits
      queries/                  # Read-only projections
      storage/                  # Checkpoint format and codecs
      migrations/               # Saved-document compatibility
      bindings/                 # Browser and portable entrypoints
    src/modules/                # Editor UI
    src/wasm-bridge/             # Thin package loader
    generated/                  # Ignored browser/server artifacts
```

## Editing and synchronization

1. The frontend submits an operation with a retry identity and expected revision.
2. Its browser worker predicts the result, separate from confirmed state.
3. The server authorizes and orders the proposal, then executes the same package
   logic against authoritative state. Repeated identities do not apply twice.
4. After durable acceptance, the server broadcasts the operation and its revision.
   Clients reconcile their pending predictions with the accepted order.
5. The host periodically publishes a package-produced checkpoint. Reconnect loads
   that checkpoint and the accepted operation suffix needed to reach current state.

Cheap deterministic edits can send intent rather than every changed pixel or object.
For an import, the intent can identify an immutable asset version and the conversion
parameters. Both hosts resolve verified bytes before mutation and apply the same
conversion. Upload first through the shared asset route, including editor shortcuts;
large source files do not become hidden upload payloads inside document operations.
Format-specific rules, such as preserving an indexed palette, belong to the package.
Asset compression is independent of the package's tile/vector/checkpoint formats.

Intent is not the only representation: nondeterministic or costly computation can
record verified result data or an immutable result reference. Initial state, missing
assets, checkpoints and recovery still transfer bytes. Accepted history retains its
inputs until recovery no longer needs them. Document sessions use WebSockets for
operations and document transfer; login, catalog and asset ingestion can use HTTP.

## Correctness and resource limits

Shared source helps consistency but does not prove determinism. Matching core and
codec versions, stable iteration/numeric behavior, and explicit inputs are necessary.
Network calls, host clocks and unrecorded randomness stay outside deterministic
mutation. Browser/server parity tests exercise equivalent state and operations.

Wasmtime fuel bounds server WASM computation per call. It is an execution budget,
not a monetary fee or a wall-clock timer. Memory, host I/O, input expansion, payload
size and concurrent work need separate bounds. A trapped execution must not leave
partially accepted state. Browser WASM does not inherit Wasmtime fuel; workers need
a cancellation/recovery policy for expensive work. Benchmark large inputs before
choosing limits rather than treating larger limits as a performance fix.

The server remains authoritative. Local predictions can be rejected; retries and
reconnects must be deduplicated. Undo belongs to the document model and must account
for other users' edits. Accepted operations and published checkpoints are separate
recovery milestones. Package ABI, edit semantics and saved formats have distinct
compatibility needs; database schema migration is a separate concern.

## Where the example helps

This design fits products needing responsive previews, collaboration, replay and
server-side validation of substantial editing rules. Its costs include two WASM
build targets, replica reconciliation, retained replay inputs and safe core upgrades.
A useful trial covers a rejected prediction, disconnect/retry, asset import,
checkpoint recovery and execution-budget failure before adopting the full pattern.

For setup mechanics, see [Rust/WASM builds](../06_backend.md#rust-and-wasm--opt-in),
[development controllers](../08_ctl.md#controllers-and-rust-development), and
[single-origin routing](../03_routing.md). Those references own the setup rules;
this example supplies one possible arrangement of the pieces.
