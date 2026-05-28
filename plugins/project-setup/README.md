# project-setup

Personal project bootstrapping plugin. Encodes Sid's conventions for laying out, configuring, and running projects — so Claude follows them automatically when initialising or working in a repo, rather than inventing fresh patterns each time.

> [!warning]
> **Work in progress.** The skill, command, and references library are landing in successive passes. Treat this as the spec, not a finished release.

## Purpose

This plugin owns the **structural and architectural side** of every repo decision. Not just "scaffold a new project" — equally **"should I add this here", "where does this belong", "split this into a package", "move compose into a folder", "add a second backend", "pick a database"**, and everything else in that surface area.

There is **no single ideal structure** — what's "right" depends on whether the project is mono- or poly-repo, has one or many backends, one or many frontends, ships ML or app code, what's getting deployed where, and a dozen other shape questions. So this plugin is not a template generator. It's:

1. A **knowledge base** of recognised project layouts and the conventions that apply to each.
2. A **question-asker** that interrogates the user (or the existing repo) before recommending anything.
3. A **decision engine** for individual architectural questions when the user is mid-work: surfaces the convention, explains the trade-off, proposes a concrete action.
4. A **layout proposer** that, when invoked for a full bootstrap, produces a concrete tree and the snippets to wire it up.

The same machinery powers initialising a new project, auditing an existing one for convention drift, suggesting an ideal structure for a half-done repo, and answering "where should this go" questions during day-to-day work.

## What gets shipped

- **One skill** — `project-setup` — the umbrella triage skill. It owns the question flow and the references library.
- **One slash command** — `/ps-setup` — with three modes:
  - `/ps-setup` — interactive init for a new project
  - `/ps-setup audit` — scan the current repo, report drift from conventions
  - `/ps-setup suggest` — propose an ideal structure for the current repo given what's there
- **References library** — `skills/project-setup/references/` — layouts, env/config rules, docker patterns, scripts, language flows, frontend, databases, modularity, the `.claude/` folder, design tokens, README contract.
- **Snippets** — `assets/snippets/` — focused fragments (tokens.css, alembic shim, vite proxy, compose overlays, the `ctl` dispatcher, `.mise.toml`) the skill cites and the slash command can drop in. **Not** a full project template.

## Layouts recognised

| # | Name | When it fits |
|---|---|---|
| 01 | single app / service | One runnable app — a CLI, library, lone backend, or lone frontend. |
| 02 | multi-app monorepo | Two or more apps in one repo, any mix of backends + frontends. Multi-backend coordination, multi-frontend `packages/` workspaces, and the microservices-mesh end are points on one spectrum — count is a parameter, not a separate layout. |
| 03 | polyrepo with deploy aggregator | Each service in its own repo plus a `-deploy` repo aggregating env + compose. |
| 04 | ML project | uvenv-driven global envs, `requirements.txt`, no frontend, no compose. |
| 05 | infra orchestrator | Docker compose tree driven by a Go CLI. |
| 06 | embeddable package + reference host | The deliverable is a published package (UI component / SDK / engine) an external host mounts; the repo's `apps/web` is a reference host, not the product. |

## ML cloud orchestration

For Layout 04 (ML projects), the skill also covers cloud GPU orchestration. Default is **dstack** — a sibling plugin in this marketplace. The `project-setup` skill defers to the `dstack` skill for CLI mechanics, focuses on the **structural** side (repo layout, `tasks/*.dstack.yml`, `scripts/cloud/`). Same support for **SkyPilot** as an alternative.

Subtopics:

- Spot-friendly training with checkpoint recovery
- Inference autoscaling + auto-redeploy on preemption
- Remote dev via SSH + VS Code Remote, Claude Code on the box
- Agent SSH access (running an agent against a remote GPU)
- ML CI/CD tiers (cheap / medium / expensive)

See `skills/project-setup/references/architecture/ml-orchestration/`.

## Key conventions encoded

- **Root `.env`** carries shared / common vars only. **Per-service `config.yaml`** in each backend reads those via `${VAR}` interpolation. Frontend has its **own** env scope (`VITE_*` / `NEXT_PUBLIC_*`) so backend secrets don't leak to clients.
- **Compose lives in `docker/`**, split on three axes: **profiles** (which services run — data core has no profile and is always up; apps opt in via `profiles: [app]`/`[edge]`), at most one **`--config=prod`** (a full alternate deployment config, `compose.prod.yaml`), and stackable **`.m.` modifiers** (`compose.m.<modifier_name>.yaml`, e.g. `--expose`/`--traefik`). Base is port-less; profiles do ~90% of the work because dev runs on the host.
- **One control dispatcher at repo root** — `ctl` — is the single entrypoint: `ctl dev` (local host loop, hot reload, auto-starts the data core) / `ctl up [profile…] [--config=prod] [--<modifier>…]` (containers — profiles select services, one config + `.m.` modifiers overlay how they run; production is `ctl up app edge --config=prod`, no separate `prod` verb) / `down`·`ps`·`logs` / `status`·`setup`·`migrate`. It is a thin wrapper delegating to `docker compose`, a process runner (`process-compose`/`mprocs`), and `scripts/*.sh`; callable bare via mise PATH.
- **Clean root, ecosystem-typed code layout.** No loose code at root. Where code lives follows the stack — Python service → `app/`, frontend → `src/`, distributable package → `src/<pkg>/` — and nesting follows service count (one → top-level `./<name>/`, several → `apps/<name>/`).
- **README documents three startup paths**: wrapper script, raw docker compose, no-docker host run.
- **Modern Python for apps** (`pyproject.toml` + `uv.lock` + `uv sync`); **classic Python for ML** (`requirements.txt` + uvenv global env).
- **Design tokens** in a single CSS file consumed by `var(--token)`. No hex, no raw px in component CSS. Light + dark via `[data-theme="dark"]` on `:root`. Light-only is allowed for marketing pages.
- **mise** is mandatory; `.mise.toml` is the runtime version contract.
- **Modularity caps**: 500-line hard, 300-line soft; folders by feature, not by kind; extract on third use.

Full spec: distributed across [`skills/project-setup/references/`](skills/project-setup/references/).

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

[PolyForm Noncommercial License 1.0.0](LICENSE). Any noncommercial use is a permitted purpose — personal projects, study, hobby work, education, public research, charitable / public-interest organisations. **Commercial use is not permitted.** For commercial-use licensing, contact `developer@neuralabs.org`.

The full license text is in [`LICENSE`](LICENSE); canonical version at <https://polyformproject.org/licenses/noncommercial/1.0.0>.
