# lefthook — pre-commit hooks

Pre-commit hook manager. Fast, language-agnostic, single-binary install. Recommended for any project that wants format-on-commit + lint-on-commit + cheap-tests-on-commit without the Python overhead of `pre-commit` (the tool).

## Why lefthook

- **Single binary** — no Python runtime requirement
- **Fast** — runs hooks in parallel by default
- **Per-language friendly** — invoke ruff, biome, cargo fmt, gofmt from one config
- **mise-installable** — pin via `.mise.toml`

## Install

```toml
# .mise.toml
[tools]
lefthook = "latest"
```

Then `mise install` brings it in. Or per-OS:

```bash
brew install lefthook
# or
curl -fsSL https://lefthook.dev/install.sh | sh
```

## `lefthook.yml` shape (Layout 02 — multi-backend example)

```yaml
# lefthook.yml at repo root
pre-commit:
  parallel: true
  commands:
    backend-python-format:
      glob: "apps/backend-python/**/*.py"
      run: cd apps/backend-python && uv run ruff format --check {staged_files}
    backend-python-lint:
      glob: "apps/backend-python/**/*.py"
      run: cd apps/backend-python && uv run ruff check {staged_files}
    backend-rust-format:
      glob: "apps/backend-rust/**/*.rs"
      run: cd apps/backend-rust && cargo fmt --check
    backend-rust-clippy:
      glob: "apps/backend-rust/**/*.rs"
      run: cd apps/backend-rust && cargo clippy --workspace -- -D warnings
    frontend-biome:
      glob: "apps/frontend/**/*.{ts,tsx,js,jsx,json}"
      run: cd apps/frontend && bun run check:format && bun run check:lint
    no-data-committed:
      run: |
        if git diff --cached --name-only | grep -E '^data/.+(\.sql|\.rdb|\.bin)$'; then
          echo "Refusing to commit data files. Stop." >&2
          exit 1
        fi

pre-push:
  commands:
    test:
      run: ctl test
```

## Activation

```bash
lefthook install      # writes git hooks pointing at lefthook
```

The `ctl` dispatcher can call this in its dev flow:

```bash
# inside ctl, in the dev setup path
if command -v lefthook >/dev/null 2>&1 && [[ ! -f .git/hooks/pre-commit ]]; then
  c_info "Installing git hooks (lefthook)…"
  lefthook install
fi
```

## Composition with mise

`.mise.toml` ensures every contributor has lefthook. `ctl` ensures hooks are wired. No manual steps after clone.

## When to skip lefthook

- Tiny projects with no team — `git commit` is short enough; no value
- CI handles all checks anyway, and the team prefers to push quickly — accept later failures
- Heavy hooks that slow commits to >5s — better to fail in CI

The compromise: **fast pre-commit, slower pre-push**. Format/lint pre-commit (sub-second); tests pre-push (acceptable to wait 30s before push).

## Alternatives

| Tool | Notes |
|---|---|
| `pre-commit` (Python) | Mature, large plugin ecosystem; Python runtime requirement |
| `husky` (JS) | JS ecosystem default; needs Node installed |
| `git hooks` directly | No tool — write `.git/hooks/pre-commit` by hand; doesn't sync across team |

Default to lefthook for new projects unless the team has a strong reason otherwise.

## Real-world reference

- See `references/handoffs/examples-registry.md` — cite a registered repo's `lefthook.yml` if one exists.

## Anti-patterns

- Skipping hooks with `git commit --no-verify` as a habit — eventually breaks CI
- Heavy hooks blocking every commit — move to pre-push
- Per-developer hook setup (not committed) — fragments setup
- Hooks that depend on tools not in `.mise.toml` — fragile
