# mise — the runtime version contract

`.mise.toml` at repo root pins every runtime the project needs. `mise install` from a clean clone must produce a working toolchain.

> **Versions in this file are illustrative, not prescriptive.** `python = "3.14"`, `node = "22"`, `rust = "1.83"`, `go = "1.23"` reflect what was current at write-time. When `/ps-setup` runs, **check the latest stable** for each runtime the project actually uses (`mise ls-remote python | tail`, `mise ls-remote node | tail`, etc.) and **ask the user** which to pin to. Different projects have different upgrade tolerance; never inherit a stale default from this file.

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

`ctl` checks `mise` is on PATH and fails loudly if not.

## Calling `ctl` by bare name

To type `ctl dev` instead of `./ctl dev`, add a project-scoped PATH entry in `.mise.toml`:

```toml
[env]
_.path = ["{{config_root}}"]   # repo root → `ctl` resolves by bare name
```

This is **project-scoped** — only active inside the project dir, and only after mise trusts the repo (`mise trust`, once per clone). That's what makes it safe, unlike `export PATH=.:$PATH` globally — the classic footgun that runs a malicious executable from any cloned repo you `cd` into.

**Keep `ctl` the single root-level executable.** Putting the repo root on PATH means every executable at root becomes a bare command inside the project, so don't scatter loose scripts there — `ctl` is the one entrypoint. Subscripts live in `scripts/` and are called *by* `ctl`, not by humans, so they don't need bare-name access (and `.sh` files on PATH are an easy way to shadow a real binary). Only if a specific script genuinely needs human bare-name invocation, add that one directory explicitly:

```toml
_.path = ["{{config_root}}", "{{config_root}}/scripts"]   # only if a script needs bare-name use
```

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
