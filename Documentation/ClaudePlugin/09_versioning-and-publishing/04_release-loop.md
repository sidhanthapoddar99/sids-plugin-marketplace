# The release loop

The standard flow to cut a new version of a plugin and ship it to consumers. Each step is mechanical; the whole loop can take 30 seconds for a self-hosted marketplace.

## The loop

1. **Edit** plugin source (skill content, command, hook, etc.)
2. **Bump** the `version` field in the plugin's `.claude-plugin/plugin.json`
3. **(Optional)** Update the marketplace entry's `version` to match (only if you set it there too — see warning below)
4. **Commit** changes to both files
5. **Tag** the release: `claude plugin tag --push` from inside the plugin directory
6. **Push** the marketplace branch (commit gets pushed alongside the tag if `--push` was used)
7. **Consumer-side**: `/plugin update <plugin>@<marketplace>` re-fetches the new version
8. **Consumer-side**: `/reload-plugins` to pick up new content in the active session

> **Don't set `version` in both `plugin.json` and the marketplace entry unless you're disciplined about keeping them in sync.** The plugin's `plugin.json` wins on resolution, so a stale value there silently masks the marketplace pin. Pick one source of truth.

## What `claude plugin tag --push` does

From inside the plugin folder:

```bash
claude plugin tag --push
```

| Step | Detail |
|---|---|
| Read `plugin.json` | Extract `name` and `version` |
| Cross-check marketplace entry | Versions must agree if both set |
| Validate plugin contents | Lightweight checks on structure |
| Check working tree clean | Refuses with dirty tree (override with `-f`) |
| Check tag uniqueness | `<name>--v<version>` must not exist (override with `-f`) |
| Create tag at HEAD | `git tag <name>--v<version>` |
| Push tag | `git push origin <name>--v<version>` |

Add `--dry-run` to preview without creating. `--force` overrides the safety checks.

The `<plugin-name>--v<version>` tag format is what dependency resolution uses — see [`02_tagging-convention.md`](./02_tagging-convention.md).

## Publishing checklist for the first public release

When taking a plugin from "internal use" to "shareable":

| Step | Why |
|---|---|
| Pick a license — replace any `TBD` placeholder in `LICENSE` with a real SPDX identifier | Legal clarity. Update `plugin.json`'s `license` field too if set |
| Bump version to `1.0.0` | The conventional "this is stable" signal. `0.x` implies in-flight |
| Write a real `README.md` | Install command, what the plugin does, screenshots, requirements |
| Verify install end-to-end in a clean directory | If it doesn't work in a clean repo, it won't work for consumers |
| Push to the marketplace's host | GitHub, GitLab, etc. — wherever the marketplace lives |
| Document the install path | README, project CLAUDE.md, marketplace listing description |

## The dogfood loop

If the plugin lives in the same repo as the marketplace (and the marketplace is one of your own projects), the release loop becomes very tight:

```
edit → bump plugin.json version → commit → push → /plugin update → /reload-plugins
```

The whole loop can be 30 seconds — compare to traditional package release (publish to registry, wait for indexing, bump consumer's lockfile, install). The plugin model trades discoverability of a centralised registry for the speed of a Git remote.

The maintainer is also consumer #1 in this setup, so any breakage shows up in their own development immediately.

## Multiple plugins in one marketplace

A marketplace can ship N plugins, each with its own version line. Consumers update them independently:

```
/plugin update plugin-a@my-marketplace
/plugin update plugin-b@my-marketplace
/plugin update                            # update everything
```

`/plugin update` walks every installed plugin and checks for new versions in their respective marketplaces.

The release loop is per-plugin: bump `plugin-a/.claude-plugin/plugin.json` and tag from `plugins/plugin-a/`. Other plugins aren't affected.

## Versioning the marketplace itself

`marketplace.json` doesn't carry a meaningful top-level version field — the marketplace is just a catalogue. What's versioned is each plugin entry. If you add a new plugin to the marketplace, existing consumers see it the next time they `/plugin marketplace update <marketplace>` (or their next `/plugin update` cycle).

If you want to version the marketplace itself for reproducibility (e.g. for `extraKnownMarketplaces` pins or audit purposes), tag the marketplace repo with a separate convention (`marketplace-v1.0.0` for example) and have consumers add it with `#marketplace-v1.0.0`.

## Common pitfalls

| Pitfall | Effect | Fix |
|---|---|---|
| Forgot to bump `version` | `/plugin update` becomes a no-op; consumers report "the new feature isn't showing up" | Bump `version` whenever shipping change worth distributing |
| Major bump without migration notes | Consumers on `1.x` surprised by `2.0` breaking changes | Document the breakage in the README and changelog |
| Pinned consumers to `0.0.1` early | Pre-1.0 churn is real | Get to `1.0` once the surface area is stable |
| Version set in both `plugin.json` and marketplace entry | Stale `plugin.json` masks marketplace bump | Pick one source of truth; usually `plugin.json` |
| Tag pushed without committing the version bump | Tag points at old version content | Commit the version bump *before* running `claude plugin tag` |

## See also

- [`02_tagging-convention.md`](./02_tagging-convention.md) — `<plugin>--v<version>` tag format and `claude plugin tag` flags
- [`03_version-resolution.md`](./03_version-resolution.md) — how the resolved version is computed
- [`05_pre-releases-and-hotfixes.md`](./05_pre-releases-and-hotfixes.md) — RC tags, hotfix bumps, and backport branches
- [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md) — running stable + latest channels off the same plugin repo
