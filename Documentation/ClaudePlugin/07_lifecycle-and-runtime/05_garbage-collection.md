# Garbage collection

Old plugin versions and orphan auto-installed dependencies are cleaned up automatically. The mechanism is conservative — there's a 7-day grace window before any deletion — so concurrent sessions that already loaded an older version can finish without errors.

## What gets GC'd

| Asset | Trigger | Window |
|---|---|---|
| Old version directories under `~/.claude/plugins/cache/<mkt>/<plugin>/<old-version>/` | Each `/plugin install` or `/plugin update` marks the **previous** version as orphaned | 7 days |
| Auto-installed dependency plugins no installed plugin requires | `claude plugin prune` (manual) | Immediate |

The cache's per-version GC is automatic; `claude plugin prune` is for the dependency closure and is explicit.

## Orphan-marking

When `/plugin update` (or a fresh `/plugin install`) writes a new version directory, the previously active version directory gets an orphan marker. The runtime tracks orphan timestamps. After 7 days from the orphan-marking timestamp, the directory is removed.

The grace window matters because:

- A long-running session that loaded `0.1.0` keeps holding open files in `0.1.0/` — if we deleted it immediately on update, those file handles would point at unlinked inodes and any disk-resolution would fail
- Users sometimes want to roll back. The 7-day window means an accidental update can be undone (manually) without re-fetching from the marketplace

There is **no on-demand "wipe orphans"** command. The timer runs automatically. If you want to free space immediately, you can `rm -rf` the orphaned version directories yourself — see [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md).

## Glob and Grep skip orphans

The runtime's file search tools (`Glob`, `Grep`) skip orphaned directories during searches. This means searches across the cache won't surface stale code from versions that are about to be GC'd. The orphan marker is the signal — once a directory is orphaned, search skips it even before the 7-day window expires.

This is also why the cache layout supports multiple coexisting versions cleanly — only the active version contributes to search results.

## `claude plugin prune` — different operation

```
claude plugin prune              # interactive
claude plugin prune --dry-run    # show what would be removed
claude plugin prune -y           # skip confirmation
```

Alias: `claude plugin autoremove`. Requires Claude Code v2.1.121+.

This removes **auto-installed dependency plugins** that no installed plugin requires. It does *not* affect cache-version GC.

When plugin A depends on plugin B, installing A also installs B as an auto-dep. If you later uninstall A, B remains installed — `claude plugin prune` is the way to remove it. The runtime tracks user-requested installs separately from auto-deps.

`claude plugin uninstall --prune` is a shorthand: uninstall this plugin **and** prune any deps that were auto-installed for it. See [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md).

## What survives uninstall vs GC

| Action | Cache version dir | Data dir | Auto-deps |
|---|---|---|---|
| `/plugin disable` | unchanged | unchanged | unchanged |
| `/plugin uninstall` (last scope) | typically cleared (sometimes survives — see [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md)) | **deleted** | **kept** unless `--prune` |
| `/plugin uninstall --keep-data` | typically cleared | preserved | kept |
| `/plugin uninstall --prune` | typically cleared | deleted | also pruned |
| `/plugin update` | old version orphaned (GC'd 7 days later) | unchanged | dep closure re-resolved |

## Diagnostic

```bash
ls ~/.claude/plugins/cache/<mkt>/<plugin>/
# Multiple version directories means at least one is orphaned

claude plugin list --json | jq '.errors'
# Range conflicts and orphan-related warnings surface here
```

## See also

- [`04_updates.md`](./04_updates.md) — when orphan-marking happens
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — manual cache wipes, when the cache survives uninstall
- [`../03_storage-and-scope/01_cache-layout.md`](../03_storage-and-scope/01_cache-layout.md) — the multi-version cache layout
- [`../12_cli-and-ui/`](../12_cli-and-ui/00_index.md) — full CLI surface including `prune`
