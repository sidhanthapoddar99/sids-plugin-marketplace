# project-setup

One skill: how a repo is shaped. It answers a bootstrap ("set up this project"), an audit ("does this repo follow the rules"), and a single question mid-task ("where does this go"). The same rules serve all three, so the answer does not depend on which one you asked.

The skill is opinionated on purpose. One repo tree, one entrypoint (`ctl`), one origin, one file per kind of value. A convention that is written once and checked by a script beats a fresh decision on every task, because an agent reads the file cold and the check does not.

## Contents

| Path | What it is |
|---|---|
| `skills/project-setup/SKILL.md` | The workflow for each mode, the page table, and the pointers into the template |
| `skills/project-setup/references/01_layout.md` to `12_http-and-tls.md` | Fifteen pages. Each owns one question: layout, env, routing, stack, frontend, backend, security, `ctl`, the compose model of `ctl up`, production, review passes, static checks, dynamic tests, conventions and audit order, HTTP and TLS |
| `skills/project-setup/template/` | The floor of the tree. `ctl`, `scripts/`, `docker/`, the env template and `AGENTS.md` are real and run. The app folders are shape only |
| `skills/project-setup/additional-template/` | The add-ons a repo gains by name: git hooks, `memory/`, a browser suite. Its `README.md` says when each is earned |
| `../../evals/project-setup/` | The test prompts and fixtures used to check the skill with skill-creator. Kept outside the plugin so installs do not carry them |

## What the template gives you

- `ctl`: one entrypoint. `ctl setup`, `ctl check`, `ctl dev`, `ctl up [--config c] +modifier`, `ctl up preset <name>`, `ctl db migrate`, `ctl test`, `ctl gate`. Run `template/ctl --help` for the list.
- `ctl gate`: the ladder. The floor is four rungs, `lint typecheck test check`, each seconds. `dead`, `audit`, `build` and `e2e` are switched on by name when the project earns them. `ctl gate static` and `ctl gate dynamic` run each half.
- `ctl check`: the repo contract. It runs every rule, prints every failure, and exits 0 only when all of them passed. It is also the `check` rung.
- One ignored root `.env` and committed `.env.template`, grouped by kind with two-line hash headers. Backends select values through `config.yaml`; frontend dev processes inherit the environment, while browser constants and Docker service keys are explicitly selected.
- `docker/compose.base.yaml` defines the whole stack without published ports. Modifiers add exposure; `docker/presets.yaml` selects saved combinations. The dev preset selects only engines and schema jobs from base with loopback database ports.
- `AGENTS.md`: the brief. Every chosen variant, exception and deferral is recorded there, and an audit compares the repo against it.

## What stays out

Docs-site content is the `agent-ks` plugin. Training loops, remote GPUs and model serving are decided per project and recorded in `AGENTS.md`. Host proxies and TLS live outside the repo.

## Install

```
/plugin install project-setup@sids-plugin-marketplace
codex plugin add project-setup@sids-plugin-marketplace
```

## Changelog

### 0.11.0 (unreleased)

- Consolidate database engines and migration jobs into the base Compose config; select development services through the dev preset with loopback database exposure.
- Replace development Nginx with native frontend proxies and rewrites; remove the separate db/dev Compose configs and development-proxy settings.
- Add routing and Compose regressions, including live Vite HTTP, WebSocket and HMR checks.

### 0.10.1

- Configure the Flyway migration directory explicitly and copy SQL files to `/migrations` inside the container, avoiding the default-folder deprecation warning.

### 0.10.0

- Add `ctl stop` and a read-only `--dry-run`: stop owned host groups and frozen servers before project containers, retaining containers and data.
- Verify shutdown, allow graceful watcher cleanup, reject unsafe process ownership, and report incomplete host or Docker shutdown.
- Add shared controller locks and a TypeScript/Watchexec Rust development example.
- Standardize PostgreSQL migrations on containerized Flyway with startup ordering and CTL commands.
- Validate development configuration and synchronize dependencies before startup, sharing the setup helpers.
- Add an optional shared-WASM document-engine example under `references/examples/`.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE). Any noncommercial use is permitted: personal projects, study, hobby work, education, public research, charitable and public-interest organisations. Commercial use is not permitted. For commercial-use licensing, contact `developer@neuralabs.org`.
