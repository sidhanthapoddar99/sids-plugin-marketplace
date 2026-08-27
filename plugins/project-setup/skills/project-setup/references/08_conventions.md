# Conventions

## Residue — a restructure is done only when nothing describes the old tree

Each of these is an audit finding. Delete or move; do not keep "just in case". Git history is the backup.

| Residue | Rule |
|---|---|
| Stale self-description | `README.md`, `AGENTS.md` or docs naming folders, paths or commands that no longer exist. Fix in the same change that moved them. |
| Graveyard folders | `old/`, `backup/`, `<thing>-v1/`, `*-old/`. Delete. |
| Retired duplicates | Two config systems, two docs sites, two tools for one job. Finish the migration and delete the loser. |
| Committed archives | Datasets, dumps, model weights, zips beside code. Move to `data/` or external storage. |
| Loose worktrees and scratch checkouts | Inside the repo or beside it. Keep them under an ignored path or outside the project folder. |
