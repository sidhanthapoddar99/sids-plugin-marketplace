# Multi-stage, built only on the server that runs it (references/16_rust-production.md):
#   1. FROM rust:<version> AS build: the same pin as .mise.toml. cargo build --release -p api, with
#      BuildKit cache mounts for the Cargo registry (one id per stage, because Cargo's package lock
#      sits outside the mount) and for target/, which a size check empties when it passes its limit.
#   2. FROM debian:<version>-slim: the binary only, run as a non-root user. A RUN line starts the binary
#      with a check flag, so an image whose binary cannot start fails to build.
