# The nested data dir trick

A small but important detail: how to bind-mount a Postgres (or similar) data directory while also keeping a committed `.gitkeep`.

## The problem

Postgres refuses to initialise into a non-empty directory. If you mount `data/postgres/` and it contains `.gitkeep`, `initdb` fails:

```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
```

But you want `.gitkeep` so the directory survives a fresh clone (`git clone` doesn't create empty dirs).

## The fix — bind-mount a NESTED dir

Mount `data/postgres/pgdata` (the empty nested dir), not `data/postgres/` (which contains `.gitkeep`).

```
data/postgres/
├── .gitkeep                    # committed — keeps the parent dir
└── pgdata/                     # bind-mounted; empty on first boot
    └── .gitkeep                # also committed — keeps the nested dir
```

Wait — that's `.gitkeep` inside `pgdata/` too. That should also break initdb?

It does. So gitignore the inner `.gitkeep` after initial setup, **or** initialise with `find data/<svc>/<inner>/ -mindepth 1 -delete` if you want a hard reset.

**Better pattern**: commit `data/postgres/pgdata/.gitkeep` and explicitly exclude it from the mount:

```yaml
services:
  postgres:
    volumes:
      - ${DATA_DIR:-./data}/postgres/pgdata:/var/lib/postgresql/data
```

Postgres will write its initdb output into `pgdata/`, alongside the `.gitkeep`. **This works because Postgres considers a directory "empty" if it contains only a hidden file like `.gitkeep`** — actually, this depends on the Postgres image. Recent images check `os.listdir()` and treat `.gitkeep` as a non-empty directory.

**Safest approach**: don't commit `.gitkeep` inside `pgdata/`. Commit it one level up, and let `ctl dev` create the `pgdata/` directory on first run:

```
data/postgres/
└── .gitkeep                    # commits parent
```

```bash
# ctl dev — data-dir setup:
mkdir -p data/postgres/pgdata data/redis/data data/seaweed/{master,volume,filer}
```

This is the **canonical pattern**. The skill should generate `ctl` with these `mkdir -p` calls baked in.

## The atheneum approach (for reference)

Atheneum commits `.gitkeep` inside the parent (`data/postgres/`), not the nested `pgdata/`. The `ctl` dispatcher creates `data/postgres/pgdata/` on first run. The bind-mount is `data/postgres/pgdata:/var/lib/postgresql/data`. Postgres initialises into the empty nested dir cleanly.

From atheneum's `docker-compose.yaml`:

```yaml
volumes:
  # Bind-mount a NESTED pgdata dir so the parent (data/postgres/) can carry
  # a committed .gitkeep without breaking initdb. Postgres refuses to
  # initialise into a non-empty directory; the nested path is empty on
  # first boot, so initdb runs cleanly.
  - ${DATA_DIR}/postgres/pgdata:/var/lib/postgresql/data
```

## Services that need this trick

| Service | Why |
|---|---|
| Postgres | initdb refuses non-empty dir |
| Redis (AOF mode) | Same issue with append-only file in non-empty dir |
| Meilisearch | Same |

Generally any service that "initialises" state on first boot.

## The other approach — use `:Z` or `:z` on SELinux

If the container can't write to the bind-mount because of SELinux:

```yaml
volumes:
  - ${DATA_DIR}/postgres/pgdata:/var/lib/postgresql/data:Z
```

Documented for completeness; orthogonal to the empty-dir issue.

## Anti-patterns

- Committing data files into `data/` — `.gitkeep` only
- Bind-mounting `data/postgres/` directly with a committed `.gitkeep` in it — initdb fails
- Removing the bind-mount because "the wrapper handles it" — you lose backups, migrate-ability, transparency
- `chmod 777 data/` to fix permissions — fix UID matching instead
