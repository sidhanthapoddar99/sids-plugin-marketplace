# Rust production builds — fast binaries, small WASM, and a server that builds them without filling its disk

This page owns the release build of Rust and WebAssembly code and the image build that runs it. Development and test builds are `10d_test-speed-and-resources.md` § Rust builds that write less; the watcher is `06_backend.md` § Rust and WASM. Read this page when a project ships its first Rust image, and again when build time or disk use grows.

The numbers below were measured on one production workspace: two Rust servers and four Rust document engines that ship as both server modules and browser WASM, built on a 16-core server.

## The release profile

Put this in the root `Cargo.toml` of every Rust workspace. The template's `apps/example-engine-rust/Cargo.toml` carries it.

```toml
[profile.release]
opt-level = 3          # full optimization; production runs this build
lto = "fat"            # link-time optimization across every crate, so calls inline across crate edges
codegen-units = 1      # one unit, so the optimizer sees the whole crate at once
strip = "debuginfo"    # no debug info in the shipped binary; panics still name their file and line
```

- What it buys: the fastest code the compiler makes, and a smaller binary, because fat LTO and one codegen unit let the optimizer inline and drop code across crates.
- What it costs: the last step of each binary's build, the fat LTO link, runs on one core. On the measured servers it took about 160 s and 95 s. That is why only release builds pay it; development and test builds keep Cargo's defaults.
- The gate and `ctl test` never build this profile. A rung that needs a built module, such as the WASM bindings a frontend's typecheck reads or a module a test loads, builds it in the dev profile with `opt-level = 1` and incremental on. The release crate is rebuilt whole on every version raise, because the version is one of its inputs, and fat LTO on one core cannot reuse a cache. On Studio four engines took 104 s that way inside one typecheck rung, while their dependencies were already cached. The release profile is built once, in the image.
- Use `opt-level = "s"` or `"z"` only when size matters more than speed, and only after you measure both, because the size gain is often smaller than the speed loss.
- Keep `panic = "unwind"` (the default) for servers, so one panicking request does not take the process down. A WASM module that never catches a panic may set `panic = "abort"`; measure the size gain before you keep it.

## WebAssembly

- Build browser WASM with `wasm-pack build --release`, and turn on `wasm-opt`, binaryen's optimizer, in the crate's `Cargo.toml`:

  ```toml
  [package.metadata.wasm-pack.profile.release]
  wasm-opt = ["-O3"]
  ```

  On the measured engines, the same release profile plus `wasm-opt -O3` made the browser files 19 to 24 % smaller, for example 8.13 MB to 6.61 MB, and the browser loads and compiles less.
- Pin binaryen. `wasm-pack` 0.12 runs the `wasm-opt` it finds on `PATH`, and otherwise downloads an old binaryen of its own choice, so an unpinned build differs between machines. Pin it in `.mise.toml` (`"github:WebAssembly/binaryen" = "version_<N>"`) and in the Dockerfile, where the image downloads that release, checks its SHA-256 and puts its `bin/` first on `PATH`.
- `ctl check` compares the pins: the Rust version, `wasm-pack` and binaryen in `.mise.toml` must equal the ones the Dockerfile names, because a host build and an image build of one commit must make the same bytes.
- When a build records what it compiled from, as an engine identity or a cache key does, include `rustc --version`, `wasm-pack --version` and `wasm-opt --version`, because each one changes the output.
- `wasm-opt` runs on the browser build only. A server module that Wasmtime loads is compiled again at load time, so it gains little.

## The image build

Build images only on the server that runs them, with BuildKit. No prebuilt image is pulled, so the build must be fast and must not fill the disk.

```dockerfile
# One base stage holds the toolchain, so every Rust stage starts from the same pins.
FROM rust:<version> AS rust-base
# … install wasm-pack and the pinned binaryen here …

# Independent stages build in parallel; BuildKit runs every stage no other stage waits on at once.
FROM rust-base AS engines
RUN --mount=type=cache,id=<project>-cargo-registry-engines,target=/usr/local/cargo/registry \
    --mount=type=cache,id=<project>-target-engines,target=/build/target \
    <build the engines>

FROM rust-base AS server-build
RUN --mount=type=cache,id=<project>-cargo-registry-server,target=/usr/local/cargo/registry \
    --mount=type=cache,id=<project>-target-server,target=/build/target \
    cargo build --release --locked -p server && cp target/release/server /out/

FROM debian:<version>-slim
COPY --from=server-build /out/server /usr/local/bin/server
# The image refuses to build when its binary cannot start or its modules do not match.
RUN server --check
USER app
```

- **Parallel stages.** One shared base stage, then the engines and each server in their own stages, which BuildKit builds at the same time. On the measured stack this took a cold build from 8 min 37 s to 5 min 49 s, and a warm one from 5 min 09 s to 3 min 38 s. A 4 to 5 times gain is not possible while fat LTO is kept, because each server's last step runs on one core.
- **One registry cache per stage.** Give each stage's Cargo registry mount its own `id`. Cargo's package lock sits in `CARGO_HOME`, outside the mount, so two stages that share one registry mount can corrupt each other's downloads.
- **Target caches with a size limit.** A `target/` cache mount keeps warm builds fast, but Cargo never deletes old outputs. Before each build, check the cache's size and empty it when it passes its limit (for example 10 GiB for the engines and 4 GiB per server). The next build is then cold once, instead of the disk filling for good.
- **Old images.** After `ctl up` starts the new images, delete the older untagged images of the project's own services, matched by the label `com.docker.compose.project=<project>`, so each deploy does not leave a few hundred MB behind.
- **The builder's own cache.** Set a limit in `/etc/docker/daemon.json`, for example `"builder": {"gc": {"enabled": true, "defaultKeepStorage": "30GB"}}`, because BuildKit keeps every layer it built until told otherwise.
- **A check inside the image.** End the final stage with a `RUN` that starts the binary in a check mode, such as checking that every module it loads matches its record. A broken image then fails to build instead of failing at the first request.

## Disk wear

A Rust workspace writes many GB per build, and an SSD has a limited number of writes. Keep the writes down:

- Release builds happen only in images, on the server; developers build dev and test profiles.
- Development and test builds keep only line tables for the workspace's own crates and no debug info for dependencies (`10d`), which cut one measured edit's writes from 15.1 GB to 4.3 GB.
- Every worktree keeps its own warm `target/` in a slot (`13_worktree.md`), and `ctl worktree trim` deletes outputs no build used for a week.
- The size limit on each image cache bounds what the server keeps.

## Checklist

Walk this when the first Rust image ships (it joins `09_production.md` § Checklist):

- [ ] the release profile above in every Rust workspace, and `wasm-opt = ["-O3"]` for every browser WASM crate
- [ ] rust, wasm-pack and binaryen pinned in `.mise.toml` and the Dockerfile, with the binaryen download checked by SHA-256; `ctl check` green
- [ ] one base stage, independent stages in parallel, one registry cache `id` per stage
- [ ] a size limit on every target cache mount
- [ ] old project images deleted after `ctl up`, and a BuildKit GC limit in `daemon.json`
- [ ] the final stage starts its binary in a check mode
- [ ] the build time, cold and warm, and the binary and WASM sizes recorded in the version log, so a later change can be compared
