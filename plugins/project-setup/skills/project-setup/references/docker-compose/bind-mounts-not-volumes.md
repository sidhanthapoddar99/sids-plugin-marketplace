# Bind-mounts, not named volumes

This project defaults to **bind-mounting host directories** for all stateful services. Docker named volumes are not used.

## What that means

```yaml
# YES — bind-mount
services:
  postgres:
    volumes:
      - ${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data

# NO — named volume
services:
  postgres:
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```

The named-volume section in compose is **deliberately empty** in our setup.

## Why bind-mount

- **Visible** — you can `ls data/postgres/pgdata` on the host and see the actual files
- **Backup-friendly** — `rsync data/ remote:backups/my-app-$(date +%F)/` works trivially
- **Migrate-friendly** — copy the data dir, deploy elsewhere, mount the same path
- **No docker-managed metadata** — what's there is what's there
- **Fewer moving parts** when troubleshooting

## Trade-offs

- **Permissions** — the container's UID must be able to write to the host directory. Use `user:` or `init: true` if needed; document it.
- **Performance on macOS/Windows** — bind-mounts can be slower than named volumes on Docker Desktop. Acceptable for our use case; production is Linux.
- **Loss of named-volume-only features** (e.g. volume drivers) — we don't need them.

## Folder discipline

State lives under `data/<service>/<subdir>/`. The `data/` folder is gitignored except `.gitkeep` files.

```
data/
├── postgres/
│   └── pgdata/           # ← bind-mounted, the actual postgres data
│       └── .gitkeep      # but wait — see "nested data dir trick"
├── redis/
│   └── data/             # bind-mounted
│       └── .gitkeep
├── seaweed/
│   ├── master/
│   ├── volume/
│   └── filer/
└── meili/
```

See `nested-data-dir-trick.md` for the `.gitkeep` interaction.

## `.gitignore` for `data/`

```
data/
!data/.gitkeep
!data/**/.gitkeep
```

This commits the directory structure (via `.gitkeep`) but not the actual data. Fresh clones can run `./dev` immediately — the directories exist.

## `${DATA_DIR}` env override

The compose files use `${DATA_DIR:-./data}`. Default is `./data` (in-repo). Override via env for:

- **Production**: `DATA_DIR=/srv/my-app/data` in `.env.production`
- **Dev on a faster disk**: `DATA_DIR=/mnt/ssd/my-app` in `.env.local`
- **Tmpfs for tests**: `DATA_DIR=/tmp/my-app` in CI

## When to break the rule

- The container produces enormous, ephemeral data (e.g. compilation caches) — a named volume is fine; document the choice
- The volume must be shared between multiple compose stacks — named volume or external bind both work; default to external bind for transparency

## Anti-patterns

- Mixing bind-mounts and named volumes for the same service — pick one
- Bind-mounting a single file when a directory would do (file-vs-directory bind has Linux gotchas)
- Forgetting `.gitkeep` and letting the directory not exist on fresh clones — compose fails with cryptic errors
- Letting `data/` get committed — large blobs in git history are forever
