# mise — the runtime version contract

`.mise.toml` at repo root pins every runtime the project needs. `mise install` from a clean clone must produce a working toolchain.

## `.mise.toml` shape

```toml
# .mise.toml
[tools]
python = "3.14"
node   = "22"
bun    = "latest"
rust   = "1.83"            # or use rust-toolchain.toml inside backend-rust/
go     = "1.23"

[env]
# Optional — env vars to apply when entering the project dir
# (rarely needed if .env handles things)
PYTHONDONTWRITEBYTECODE = "1"
```

Pin major versions. Avoid `latest` for production runtimes (Bun is a pragmatic exception — it changes fast and is mostly backward-compatible).

## Per-language overrides

- **Rust**: also commit `rust-toolchain.toml` inside `apps/backend-rust/` for tooling that respects it (rustup, cargo). The mise pin is the install hint; the toolchain file is what cargo respects.

  ```toml
  # apps/backend-rust/rust-toolchain.toml
  [toolchain]
  channel = "1.83"
  components = ["rustfmt", "clippy", "rust-analyzer"]
  ```

- **Node / Bun**: mise covers it; no `.nvmrc` needed.
- **Go**: mise covers it; `go.mod`'s `go 1.23` directive is also enforced by `go build`.

## Why mise (not asdf / pyenv / nvm / volta)

- **One tool** — Python, Node, Rust, Go, Java, Ruby, all in one
- **Fast** — Rust-based, no per-language plugin overhead
- **Direct env support** — sets vars when entering a directory (`[env]` block)
- **Project + user + global** scopes — fewer surprises than asdf
- **Modern UX** — `mise install` is the one command

## Install instructions in `.env.example` / README

```bash
# from README
curl https://mise.run | sh
mise install
```

`./dev` checks `mise` is on PATH and fails loudly if not.

## CI

GitHub Actions:

```yaml
- uses: jdx/mise-action@v2
- run: mise install
```

Self-hosted runner: pre-install mise on the runner image.

## When NOT to use mise

- Heavy specialised stacks (e.g. CUDA + specific torch + specific Python) — pyenv / conda may have wider community support
- Org policy requires asdf / specific manager — accommodate

## Anti-patterns

- `.python-version`, `.nvmrc`, `.tool-versions` all in one repo — pick mise and stick
- mise + the language's own version manager (`pyenv install 3.14` then `mise install`) — conflict
- Pinning `latest` for everything — breaks reproducibility
- No version pin at all — "works on my machine"
