# project-setup

Personal project bootstrapping plugin. Encodes Sid's conventions for laying out, configuring, and running projects — so Claude follows them automatically when initialising or working in a repo, rather than inventing fresh patterns each time.

> [!warning]
> **Work in progress.** The skill, command, and references library are landing in successive passes. Treat this as the spec, not a finished release.

## Purpose

There is **no single ideal structure** — what's "right" depends on whether the project is mono- or poly-repo, has one or many backends, one or many frontends, ships ML or app code, and many other shape questions. So this plugin is not a template generator. It's:

1. A **knowledge base** of recognised project topologies and the conventions that apply to each.
2. A **question-asker** that interrogates the user (or the existing repo) before recommending anything.
3. A **layout proposer** that, only after the questions are answered, suggests a concrete tree and the few snippets needed to wire it up.

The same machinery powers initialising a new project, auditing an existing one for convention drift, and suggesting an ideal structure for a half-done repo.

## What gets shipped

- **One skill** — `project-setup` — the umbrella triage skill. It owns the question flow and the references library.
- **One slash command** — `/ps-setup` — with three modes:
  - `/ps-setup` — interactive init for a new project
  - `/ps-setup audit` — scan the current repo, report drift from conventions
  - `/ps-setup suggest` — propose an ideal structure for the current repo given what's there
- **References library** — `skills/project-setup/references/` — topologies, env/config rules, docker patterns, scripts, language flows, frontend, databases, modularity, the `.claude/` folder, design tokens, README contract.
- **Snippets** — `assets/snippets/` — focused fragments (tokens.css, alembic shim, vite proxy, compose overlays, the `./dev` wrapper, `.mise.toml`) the skill cites and the slash command can drop in. **Not** a full project template.

## Topologies recognised

| # | Name | When it fits |
|---|---|---|
| 01 | single-app | A single CLI / library / tool. No frontend, no microservices. |
| 02 | monorepo, 1 backend + 1 frontend | The common product case. |
| 03 | monorepo, multi-backend microservices | Two or more backends in different languages coordinating via Redis/DB (e.g. atheneum: Python control plane + Rust data plane). |
| 04 | monorepo, multi-frontend workspaces | Several frontends sharing a `packages/ui` (e.g. plane: web/admin/space/live + shared packages, turborepo + pnpm). |
| 05 | monorepo, microservices mesh | Many small backends each with their own boundary. |
| 06 | polyrepo with deploy aggregator | Each service in its own repo plus a `-deploy` repo aggregating env + compose. |
| 07 | ML project | uvenv-driven global envs, `requirements.txt`, no frontend, no compose. |
| 08 | infra orchestrator | Docker compose tree driven by a Go CLI (e.g. chimere multinode blockchain). |

## Key conventions encoded

- **Root `.env`** carries shared / common vars only. **Per-service `config.yaml`** in each backend reads those via `${VAR}` interpolation. Frontend has its **own** env scope (`VITE_*` / `NEXT_PUBLIC_*`) so backend secrets don't leak to clients.
- **Compose lives in `docker/`**, with files representing **deployment modes** (`compose.yaml`, `compose.database-only.yaml`, `compose.dev.yaml`, `compose.prod.yaml`, `compose.traefik.yaml`, `compose.no-ports.yaml`).
- **One global wrapper at repo root** — `./dev` — is the single entrypoint. It dispatches to subcommands and to scripts in `scripts/`. Setup folds in (no separate `setup.dev.sh`).
- **No `src/` at repo root.** Always nest inside an `apps/<name>/src/` (or similar) so there's room to grow without restructuring.
- **README documents three startup paths**: wrapper script, raw docker compose, no-docker host run.
- **Modern Python for apps** (`pyproject.toml` + `uv.lock` + `uv sync`); **classic Python for ML** (`requirements.txt` + uvenv global env).
- **Design tokens** in a single CSS file consumed by `var(--token)`. No hex, no raw px in component CSS. Light + dark via `[data-theme="dark"]` on `:root`. Light-only is allowed for marketing pages.
- **mise** is mandatory; `.mise.toml` is the runtime version contract.
- **Modularity caps**: 500-line hard, 300-line soft; folders by feature, not by kind; extract on third use.

Full spec: [`summary.md`](summary.md).

## Installation (when complete)

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
/plugin install project-setup@sids-plugin-marketplace
```

## Examples referenced

- `atheneum` (multi-backend Python + Rust monorepo) — `~/projects/02_OpenSource/04_knowledge_management/atheneum`
- `NeuraSutra/neurasutra-api-management` (canonical 1be + 1fe) — `~/projects/06_04_NeuraSutra/neurasutra-api-management`
- `chimere-chain-2025` (infra orchestrator with Go CLI) — `~/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025`
- `plane` (multi-frontend workspaces) — `~/projects/03_Self_Hosted_Apps/plane`

These are not perfect — they evolved at different times with different constraints. The skill cites them as evidence, not as gospel.

## License

TBD — pending decision before first release.
