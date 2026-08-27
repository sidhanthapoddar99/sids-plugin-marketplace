# Layout — the one repo shape

Every repo takes this shape. There are no layout variants to pick. A repo with one app and a repo with five apps look the same from the root.

## The tree

```
<repo>/
├── apps/                       # every runnable or shared unit, even when there is only one
│   ├── <backend>/              # one folder per backend service        (api/, api-admin/)
│   │   ├── app/                #   Python code lives here. No src/.
│   │   ├── config.yaml         #   service config. Reads ${VAR} from root .env
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   └── README.md
│   ├── <frontend>/             # one folder per frontend                (web/, admin/)
│   │   ├── src/
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── <desktop|mobile>/       # only if the product ships one. Reuses packages/
│   ├── packages/               # shared code. One folder per package    (ui/, types/, api-client/)
│   │   └── <package-name>/
│   │       └── package.json    #   or pyproject.toml. The manifest lives inside the package
│   ├── database/               # committed DB config: migrations, init scripts, sqlite schema
│   ├── infra/                  # infrastructure code: IaC, cloud wrappers, edge config
│   └── notebooks/              # exploration notebooks. Never imported by an app
├── scripts/                    # ctl workers: common/ dev/ container/ config/ test/
├── docker/                     # compose.base.yaml + standalone configs + .m. modifiers
├── data/                       # runtime state, gitignored. Only .gitkeep is committed
│   └── test_build/             #   frozen build snapshots from `ctl build save`
├── docs/                       # only when docs live in this repo
├── memory/                     # agent working rules. AGENTS.md links here
├── .env                        # secrets. gitignored
├── .env.example                # the env contract. committed
├── .mise.toml                  # tool version contract
├── .gitignore
├── .dockerignore
├── ctl                         # the single entrypoint. Thin router into scripts/
├── AGENTS.md                   # the agent brief. The real file
├── CLAUDE.md -> AGENTS.md      # symlink
├── README.md
└── LICENSE
```

## Placement rules

### Root

The root holds config, the brief, and folders. Never loose code.

| Entry | Holds | Rule |
|---|---|---|
| `apps/` | All code: apps, packages, database, infra, notebooks | One app is still `apps/<name>/`. Same shape in every repo. |
| `scripts/` | `ctl` workers | Copied from `assets/scripts/`. Adapted by deletion. |
| `docker/` | Compose files | Compose lives here, never in `apps/infra/`. |
| `data/` | Runtime state: DB volumes, uploads, checkpoints, caches, `test_build/` snapshots | Gitignored. Only `.gitkeep` is committed. Bind mounts point here. |
| `docs/` | Docs site, built with `agent-ks` | Exists only when this repo is the docs home. Projects that share a docs repo have no `docs/` folder. |
| `memory/` | Agent working rules, one file per rule set | `AGENTS.md` links here. |
| `.env` / `.env.example` | Secrets / the env contract | `.env` gitignored. `.env.example` committed. |
| `.mise.toml` | Tool version contract | |
| `.gitignore` / `.dockerignore` | Ignore lists | Curated per ecosystem present. |
| `ctl` | The single entrypoint | Thin router into `scripts/`. |
| `AGENTS.md` | The agent brief | The real file. `CLAUDE.md` is a symlink to it. |
| `README.md` / `LICENSE` | | |

> No workspace. `package.json`, `bun.lock`, `pnpm-workspace.yaml` never live in the root or in `apps/`. Each app and each package owns its own manifest and lock.

### Inside `apps/`

| Entry | Holds | Rule |
|---|---|---|
| `<backend>/` | One backend service | Python code in `app/`, no `src/`. Owns `README.md`, `pyproject.toml`, `config.yaml`, `Dockerfile`. |
| `<frontend>/` | One frontend | Code in `src/`. Owns `README.md`, `package.json`, `Dockerfile`. |
| `<desktop>/`, `<mobile>/` | A native surface | Only if the product ships one. Shares `packages/`. A PWA is the web frontend plus a manifest, not an app. |
| `packages/<name>/` | Shared code | Manifest and lock live inside the package. An app never imports from another app. It imports from a package by a `link:` dependency (`"@scope/name": "link:../packages/name"`), not by a workspace. Published package code in `src/<pkg>/`. |
| `database/` | Committed DB config: migrations, init scripts, schema | One owner, even when two backends share the DB. |
| `infra/` | IaC, cloud wrappers, edge config (nginx, Traefik) | Not compose. Containers that need a config file read it from here. |
| `notebooks/` | Exploration notebooks | Never imported by an app. Code an app needs moves into a package. |

## Three more rules

- **A folder exists only when used.** Do not scaffold an empty `docker/`, `infra/`, `data/` or `docs/` for later.
- **A published package is still a package.** When the product is a library or SDK, it lives in `apps/packages/<name>/`. The frontend next to it is a dev harness: `"private": true`, and the README's first line says so.
- **ML projects use the same tree.** The training code is `apps/<name>/`. Per-experiment settings go in `apps/<name>/configs/<experiment>.yaml`, not `config.yaml`. Datasets, checkpoints and outputs go in `data/`. There is no `docker/`.

## `.gitignore`

One file at the root. Curated for the ecosystems present, not a kitchen-sink template. Source: `assets/env/gitignore.template`.

| Section | Entries |
|---|---|
| Secrets | `.env*` except `.env.example`. `config.local.yaml`. At root and inside every app. |
| Runtime state | `data/**` with the negation below, so empty folders survive. |
| Ecosystem artifacts | Only for ecosystems present: `__pycache__/`, `.venv/`, `node_modules/`, `dist/`, `target/`, tool caches. |
| Logs and OS junk | `*.log`, `.DS_Store`. |

```gitignore
data/**
!data/**/
!data/**/.gitkeep
```

Not blanket-ignored: `.vscode/` and `.claude/`. Commit the files that carry project config (launch configs, project settings). Ignore the personal ones (`settings.local.json`).

## README — two levels

- **Root `README.md`** documents three start paths, in this order: prerequisites (`mise install`, `cp .env.example .env`), quick start with `ctl` (`ctl dev`, `ctl up`), manual without `ctl`. Plus one paragraph of architecture and the project layout.
- **Every app owns a `README.md`**: how to run it on the host from its own folder, the env vars it needs, how to test it.
- A README that describes a tree the repo no longer has is worse than no README. Update it in the same change that moves the tree.

## Naming

- App folders take the role name, not the stack name. `api/`, `web/`, `client/`, `engine/`, with an optional suffix.
    - `api/` --> `api-admin/` `api-platform/`.
    - `web/` --> `web-admin/` `web-platform/`. 
- Package folders take the thing they export. `ui/`, `types/`, `api-client/`.

## Exceptions

- The tree above yields when a host program demands its own structure. The host's contract wins; do not wrap it in `apps/`.
- Examples: VS Code extension, browser extension, host-app plugin (Jellyfin, Obsidian), plugin marketplace (Claude Code, Codex).
- Keep `ctl`, `scripts/`, `.mise.toml` only when the host allows them and they earn their place. Record the exception in `AGENTS.md`.
