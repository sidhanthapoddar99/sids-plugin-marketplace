# Layout — the one repo shape

Every repo takes this shape. A repo with one app and a repo with five apps look the same from the root. The only choice inside it is single frontend or frontend group, decided by count.

## The tree

```
<repo>/
├── apps/                       # every runnable or shared unit, even when there is only one
│   ├── <backend>/              # one folder per backend service        (api/, engine/)
│   │   ├── app/                #   Python code lives here. No src/. Rust: crates/ by layer; Go: cmd/ + internal/
│   │   ├── config.yaml         #   service config. Reads ${VAR} from the root env files
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   └── README.md
│   ├── <single-frontend>/      # OR: the only static frontend, own image (web/)
│   │   ├── Dockerfile          #   build, then nginx: the edge
│   │   └── nginx/              #   the edge template lives with the app that owns the image
│   ├── <frontend-group>/       # every static frontend, one image        (multi-web-app/)
│   │   ├── Dockerfile          #   one build stage per frontend, ends in nginx: the edge
│   │   ├── nginx/              #   nginx.conf.template (prod edge), nginx-dev.conf.template + nginx-dev-headers.conf (dev proxy)
│   │   ├── README.md
│   │   └── <name>/             #   one folder per static frontend         (app/, landing/, docs/)
│   │       ├── src/
│   │       ├── package.json
│   │       └── README.md
│   ├── <server-frontend>/      # a frontend that is a server (Next.js SSR)  (dashboard/). Own Dockerfile
│   ├── <desktop|mobile|cli>/   # only if the product ships one
│   ├── packages/               # shared code. One folder per package    (ui/, types/, tsconfig/)
│   │   └── <package-name>/
│   │       └── package.json    #   or pyproject.toml. The manifest lives inside the package
│   ├── database/               # committed DB config, one folder per engine (postgres/, neo4j/, redis/)
│   ├── notebooks/              # exploration notebooks. Never imported by an app
│   └── .dockerignore           # the frontend image builds with context ./apps; root ignores do not apply
├── scripts/                    # ctl workers: common/ config/ dev/ container/ db/ test/
├── docker/                     # compose.db compose.base compose.dev compose.m.*
├── data/                       # actual data: engine mounts, datasets, uploads
│   └── .gitignore              #   `**` and `!.gitignore`
├── logs/                       # produced state: logs, pids, backups, frozen builds
│   └── .gitignore              #   same two lines
├── docs/                       # only when docs live in this repo
├── memory/                     # agent working rules. AGENTS.md links here
├── .env.secrets.template       # every secret, blank. committed. ctl setup → .env.secrets (gitignored)
├── .env.data.template          # every path. committed. → .env.data
├── .env.proxy.template         # every host, port, prefix. committed. → .env.proxy
├── .mise.toml                  # tool version contract
├── .gitignore
├── .dockerignore
├── lefthook.yml
├── ctl                         # the single entrypoint. Thin router into scripts/
├── AGENTS.md                   # the agent brief. The real file
├── CLAUDE.md                   # one line: @AGENTS.md
├── README.md
└── LICENSE
```

The template is an instance of this tree: `template/`. Copy it, delete what the product does not need. Its app folders carry the stack in their names (`example-api-python`) to label the examples; a real project uses role names. It ships no lock files (every dependency is `<version>`); `ctl setup` creates them. `docs/`, `notebooks/`, desktop and mobile are absent because a folder exists only when used.

## Placement rules

### Root

The root holds config, the brief, and folders. Never loose code. Before creating any folder, one test: a thing you run or deploy is an app (`apps/<name>/`); a thing you import or publish is a package (`apps/packages/<name>/`). Nothing is both.

| Entry | Holds | Rule |
|---|---|---|
| `apps/` | All code: apps, packages, database, notebooks | One app is still `apps/<name>/`. Same shape in every repo. |
| `scripts/` | `ctl` workers | Copied from `template/scripts/`. Adapted by deletion. |
| `docker/` | Compose files | `compose.db`, `compose.base`, `compose.dev`, `compose.m.*`. Compose lives here, never inside an app. |
| `data/` | Actual data: engine mounts (`postgres/`, `redis/`, `neo4j/`), datasets, uploads, checkpoints | Bind mounts point here. Self-ignored; see `.gitignore` below. |
| `logs/` | Produced state: `dev/` logs, `run/` pids, `backups/`, `test_build/` | Everything `ctl` writes that is not data. Self-ignored. |
| `docs/` | Docs site, built with `agent-ks` | Exists only when this repo is the docs home. One product has one docs home: never an in-repo `docs/` and a docs repo both. To scaffold, tell the user to run `/agent-ks-init`; it is interactive, never chain into it. |
| `memory/` | Agent working rules, one file per rule set | `AGENTS.md` links here. |
| `.env.secrets.template`, `.env.data.template`, `.env.proxy.template` | The env contract in three roles: secrets, paths, routing | Committed. `ctl setup` copies each to `.env.<role>`, gitignored. See `02_env.md`. |
| `.mise.toml` | Tool version contract | Its `[env]` block puts the repo root on `PATH` (`_.path = ["{{config_root}}"]`), which is what makes `ctl` run bare. So `ctl` must stay the only executable at the root: a stray script there becomes a bare command. `mise trust` once per clone. |
| `.gitignore` / `.dockerignore` | Ignore lists | Curated per ecosystem present. Tool config that spans the whole repo (`knip.json`) may sit at root; lint config for one ecosystem sits in the app (`biome.json`, `.oxlintrc.json`, `ruff` in `pyproject.toml`). |
| `ctl` | The single entrypoint | Thin router into `scripts/`. |
| `AGENTS.md` | The agent brief | The real file. `CLAUDE.md` holds one line: `@AGENTS.md`. |
| `lefthook.yml` | Git hooks | Every hook calls `ctl` (`ctl gate lint --staged`, `ctl test`), never a tool directly. |
| `README.md` / `LICENSE` | | |

> No workspace. `package.json`, `bun.lock`, `pnpm-workspace.yaml` never live in the root, in `apps/`, or directly in the frontend group folder. Each app and each package owns its own manifest and lock. `ctl check` fails on it.

### Inside `apps/`

| Entry | Holds | Rule |
|---|---|---|
| `<backend>/` | One backend service | Python code in `app/`, no `src/`: `main.py`, `config.py`, `db.py`, `core/`, `health/`, one `<domain>/` slice per domain (`models`, `repository`, `service`, `router`). Rust: a workspace of crates by layer (`common`, `data`, `auth`, `api`). Go: `cmd/<name>/` + `internal/`. Owns `README.md`, manifest, `config.yaml`, `Dockerfile`. `config.local.yaml` is the developer's, gitignored. |
| `<frontend-group>/<name>/` | One static frontend (Vite, Next.js export, Astro) | Code in `src/`; `e2e/`, `public/`, extra HTML entrypoints as needed. Owns `README.md`, `package.json`, lock, `tsconfig.json`, its lint config. No env file. The group owns the one `Dockerfile`, `nginx/` (prod template, dev-proxy template and its headers include) and a `README.md`. Exactly one frontend owns `/`; it has no `_PREFIX` key. |
| `<single-frontend>/` | The only static frontend of the product | Code in `src/`, theme and shadcn components inside it (`src/styles/`, `src/components/ui/`). Owns `README.md`, `package.json`, lock, `tsconfig.json`, `Dockerfile` (build, then nginx), `nginx/` with its edge template. No env file. `vite.config.ts` proxies in dev. Template: `example-single-web-app-vite/`. Switch to the group when a second static frontend arrives. |
| `<server-frontend>/` | A frontend that is a server (Next.js SSR) | Its own app, own `Dockerfile`, own compose service. Never inside the group. |
| `<desktop>/`, `<mobile>/`, `<cli>/` | A native surface | Only if the product ships one. Desktop shares `packages/`; mobile shares only the API contract; a Go CLI is `cmd/` + `internal/`, built by `ctl build cli` into `bin/`, gitignored. A PWA is the web frontend plus a manifest, not an app. |
| `packages/<name>/` | Shared code | Manifest and lock live inside the package. An app never imports from another app. It imports from a package by a `link:` dependency (`"@scope/name": "link:../packages/name"`, `../../` from inside a group), not by a workspace. The `../` ban in `02_env.md` is about compose and env files, not manifests. Published package code in `src/<pkg>/`. |
| `database/<engine>/` | Committed DB config per engine: migrations, init scripts, server config | One owner, even when two backends share the DB. Hand-written migrations live here; see `06_backend.md`. |
| `notebooks/` | Exploration notebooks | Never imported by an app. Code an app needs moves into a package. |

## One repo or two

One repo is the default. A part earns its own repo only on one of three grounds: an independent release cadence that is real today, external consumers, or a visibility boundary. None of the three → it is a folder under `apps/`. Two repos never write the same tables; if they need to, the split was wrong. Between repos, share by a published package first, a pinned git ref second, a vendored copy with recorded provenance last; never a `../sibling` path as a build input. A folder that grows external consumers is the trigger to re-evaluate. Aggregator repos that compose other repos' images are out of scope for this skill.

## Three more rules

- **A folder exists only when used.** Do not scaffold an empty `docker/`, `data/`, `logs/` or `docs/` for later. There is no `infra/`: the edge config lives with the frontend that owns the image, and any host proxy (Traefik, TLS) sits outside this repo.
- **A published package is still a package.** When the product is a library or SDK, it lives in `apps/packages/<name>/`. The frontend next to it is a dev harness: `"private": true`, and the README's first line says so.
- **ML projects use the same tree.** The training code is `apps/<name>/`. Per-experiment settings go in `apps/<name>/configs/<experiment>.yaml`, not `config.yaml`. Datasets and checkpoints go in `data/`, with a committed `data/README.md` saying where the real data lives and how to fetch it. Logs and run outputs in `logs/`. Usually no `docker/`. Training loops, remote runs and serving belong to a separate ML skill; see `04_stack.md`.

## Ignore files

Root `.gitignore`: curated for the ecosystems present, not a kitchen-sink template. Source: `template/.gitignore`. Root `.dockerignore` for backend build contexts; `apps/.dockerignore` for the frontend image, whose context is `./apps`.

| Section | Entries |
|---|---|
| Env files and local overrides | `.env`, `.env.*`, `!.env.*.template`. `config.local.yaml`. |
| Runtime state | Not here. `data/.gitignore` and `logs/.gitignore` own it. |
| Ecosystem artifacts | Only for ecosystems present: `__pycache__/`, `.venv/`, `node_modules/`, `dist/`, `target/`, tool caches. |
| Logs and OS junk | `*.log`, `.DS_Store`. |

```gitignore
# data/.gitignore and logs/.gitignore — the whole file
**
!.gitignore
```

The rule travels with the folder. No `.gitkeep`, no root negation pattern. `ctl setup` creates `data/<engine>` per engine and `logs/{dev,run,backups,test_build}`. The same two lines work for any other state folder.

Not blanket-ignored: `.vscode/` and `.claude/`. Commit the files that carry project config (launch configs, project settings). Ignore the personal ones (`settings.local.json`).

## README — two levels

- **Root `README.md`** documents three start paths, in this order: prerequisites (`mise install`, `ctl setup`), quick start with `ctl` (`ctl dev`, `ctl up`), manual without `ctl`. Plus one paragraph of architecture and the project layout. Template: `template/README.md`.
- **Every app owns a `README.md`**: how to run it on the host from its own folder with native commands, the env keys it needs, how to test it. It never mentions `ctl`, so the app stays portable if lifted out. The root README points; the app README details; host setup is never written in both.
- A README that describes a tree the repo no longer has is worse than no README. Update it in the same change that moves the tree.

## Naming

- App folders take the role name, not the stack name. `api/`, `engine/`, `dashboard/`, `cli/`, with an optional suffix: `api-admin/`, `api-platform/`.
- The frontend group takes a name that says it is a group: `multi-web-app/`. Its children take the surface: `app/`, `landing/`, `docs/`, `admin/`.
- Package folders take the thing they export. `ui/` (theme and components together), `types/`, `tsconfig/`; later `services/`, `hooks/` (`05_frontend.md`).

## Exceptions

- The tree above yields when a host program demands its own structure. The host's contract wins; do not wrap it in `apps/`.
- Examples: VS Code extension, browser extension, host-app plugin (Jellyfin, Obsidian), plugin marketplace (Claude Code, Codex).
- Keep `ctl`, `scripts/`, `.mise.toml` only when the host allows them and they earn their place. Record the exception in `AGENTS.md`.
- A pure open-source package repo, where the repo *is* the published artifact and contributors expect the ecosystem's root manifest (`package.json`, `pyproject.toml` at the root), may take that shape as a recorded choice. `ctl check` reads the choice from `AGENTS.md` (`Exceptions: root-manifest`) and skips the no-workspace rule for it.
