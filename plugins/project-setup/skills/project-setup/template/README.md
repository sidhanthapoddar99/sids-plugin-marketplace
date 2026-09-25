# <project>

One paragraph: what this product is and which apps make it.

## Prerequisites
- `mise install` — installs every toolchain pinned in `.mise.toml`
- `ctl setup` — creates `.env` from `.env.template`, generates declared local credentials, creates configured data/log/backup directories, installs and activates tools

## Quick start with ctl
- `ctl dev` — databases in docker, apps on the host; frontend dev servers proxy backend requests
- `ctl clean rust` — remove local Rust debug builds and managed Rust dev logs after stopping the Rust app (`--dry-run` lists targets)
- `ctl stop` — stop managed host processes and project containers, keeping data (`--dry-run` previews targets)
- `ctl up` — full stack in docker; `ctl up preset <name>` runs a saved line from `docker/presets.yaml`
- `ctl db migrate` — apply schema migrations (they also run whenever the engines come up)
- `ctl gate` — the ladder; green here is the only definition of green

## Commands
| Verb | Does |
|---|---|
| `ctl dev [app…]` | engines in docker, the chosen apps on the host with reload |
| `ctl clean rust [--dry-run]` | remove Rust `target/debug` and managed Rust dev/controller logs; keep release builds and shared caches |
| `ctl stop [--dry-run]` | stop recorded dev/watch/build groups, then project containers; retain containers and volumes |
| `ctl up [--config c] [+modifier…] [--services a,b]` | a stack shape in docker, or a subset; interactive in a terminal |
| `ctl up preset [<name>]` · `ctl up set-preset` | run a saved `up` line · save one from the pickers |
| `ctl db migrate [new "<msg>"]` | apply or create a migration |
| `ctl manage ops\|settings` | the break-glass operator console |
| `ctl test [app\|e2e]` · `ctl gate [static\|dynamic] [-q]` | one suite, or the ladder, or half of it |
| `ctl setup` · `ctl check` · `ctl status` | create env files and deps · the repo contract · the doctor |

`ctl --help` is the full list and is always current; this table is a summary.

## Manual, without ctl
Each app's `README.md` shows how to run it from its own folder, the env keys it reads, and how to test it.

## CTL requirements

Host process supervision requires Linux or WSL, Bash, `/proc`, util-linux (`setsid`, `flock`) and GNU coreutils. Container startup also requires Docker Compose with dependency builds and `jq`. `ctl setup` activates declared mise tools before dependency commands; a selected app checks only its own runtime.

Local credential generation is declared in `scripts/config/generated-credentials.conf`. Required supplied credentials are listed in `scripts/config/required-credentials.conf`. Provider credentials are never generated. Preserve the `.env.template` contract when adapting these lists.

`DATA_DIR`, `LOGS_DIR` and `BACKUP_DIR` may be root-relative or absolute. CTL uses those configured paths for setup, process records, logs, backups and frozen builds. Development probes live in `scripts/dev/_apps.sh`; startup fails when they do not become ready. Container startup builds before activation and waits for readiness; runtime failure requires an operator recovery policy.

## Stack
| Area | Pick |
|---|---|
| Backend | Python `<version>` / FastAPI · Rust `<version>` / Axum · Go `<version>` (CLI) |
| Frontend | TypeScript, Vite `<version>`, Next.js `<version>`, Astro `<version>`, Tailwind v4, shadcn |
| Data | Postgres `<version>` + pgvector · Redis `<version>` · Neo4j `<version>` |
| Containers | docker compose ≥ 2.24; engines in docker for dev, everything for prod |
| Config | `.env` + per-backend `config.yaml` |
| Dev | mise · uv · bun |

## Documentation
`docs/` when this repo is the docs home (`agent-ks`); otherwise the docs repo is named in `AGENTS.md`.

## Lock files
The template ships no `bun.lock`, `uv.lock` or `Cargo.lock`: every dependency is a `<version>` placeholder. `ctl setup` installs and creates them. Commit them.

## Layout
```
apps/      example-api-python example-engine-rust example-multi-web-app/{landing,app,docs}
           example-single-web-app-vite example-dashboard-nextjs example-tui-go packages database
docker/    compose.base + modifiers · compose.m.<modifier> · presets.yaml
scripts/   ctl workers
data/      actual data: engine mounts, datasets. gitignored
logs/      produced state: logs, pids, backups, frozen builds. gitignored
.env.template   the grouped env contract (committed); ctl setup creates the ignored root .env
```

## Architecture
One paragraph: one origin. landing (Next.js export) at `/`, app (Vite) at `/app`, docs (Astro) at `/docs` — all in the `web` nginx image, which also proxies dashboard (Next.js SSR) at `/dashboard`, api (FastAPI) at `/api`, engine (Rust) at `/engine`. Postgres, Redis, Neo4j behind.
