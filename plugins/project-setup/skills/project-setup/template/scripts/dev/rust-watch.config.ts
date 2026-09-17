// Adapt source paths and commands together. Commands run in order, from the repo root.
// For WASM, prepend your package's development build command and include its sources.
// Keep generated bindings and target directories out of paths.
export default {
  paths: ['apps/example-engine-rust/src', 'apps/example-engine-rust/crates',
    'apps/example-engine-rust/Cargo.toml', 'apps/example-engine-rust/Cargo.lock'],
  commands: [['cargo', 'run', '--manifest-path', 'apps/example-engine-rust/Cargo.toml']],
  debounceMs: 500,
};
