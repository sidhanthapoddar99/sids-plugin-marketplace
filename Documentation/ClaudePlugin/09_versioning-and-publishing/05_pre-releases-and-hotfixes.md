# Pre-releases and hotfixes

The pre-release suffix on a semver version (`-rc.1`, `-beta.2`, `-alpha`) flows through the tagging convention and dependency-range resolution intact. There's no first-class "yank" mechanism — hotfixes are just patch bumps. Backports use release branches.

## Pre-release tags

A pre-release version uses the standard semver suffix on the version, which then carries into the [`<plugin>--v<version>` tag format](./02_tagging-convention.md):

```
deploy-kit--v2.0.0-rc.1
deploy-kit--v2.0.0-rc.2
deploy-kit--v2.0.0-beta.3
plugin-name--v3.0.0-alpha.1
```

`plugin.json` carries the same value:

```json
{
  "name": "deploy-kit",
  "version": "2.0.0-rc.1"
}
```

Tag with `claude plugin tag --push` as usual. The tag format is unchanged — the suffix just rides through.

## Pre-release exclusion in dependency ranges

By default, semver ranges **exclude** pre-release versions from matching:

| Range | Matches `2.0.0-rc.1`? |
|---|---|
| `^2.0.0` | No |
| `>=2.0.0` | No |
| `^2.0.0-0` | Yes (opts in to pre-releases at or above `2.0.0-0`) |
| `>=2.0.0-rc` | Yes |

This means consumers on `^2.0.0` won't accidentally pick up `2.0.0-rc.1` even if it's the latest tag. To opt in, declare the dependency with an explicit pre-release suffix in the range.

## Installing a pre-release

There's no `--version` flag on `/plugin install`. To pull a specific pre-release tag, consumers pin via one of:

- **Marketplace entry's `version` or `ref`/`sha`** — for plugin authors who want to expose pre-releases as a separate channel:

  ```json
  {
    "name": "deploy-kit",
    "source": { "source": "github", "repo": "acme/deploy-kit", "ref": "v2.0.0-rc.1" }
  }
  ```

- **Separate beta marketplace** — keep stable on `main` and pre-releases on a `beta` branch; consumers who want pre-releases add the marketplace at `#beta`. See [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md).

- **Consumer's own dependency range** — if the pre-release is a dependency of another plugin, declaring `^2.0.0-0` or `>=2.0.0-rc` opts in to pre-release versions during dependency resolution.

The pre-release stays installed until the consumer runs `/plugin update` and a newer version overwrites it.

## Hotfixes — just patch bumps

There's no formal "yank" or "deprecate" mechanism. If `2.1.0` ships a regression, the fix flow is:

1. Fix the bug
2. Bump `plugin.json` version to `2.1.1`
3. `claude plugin tag --push`
4. Consumers running `/plugin update` get `2.1.1`

If the regression is bad enough that you want consumers to actively skip `2.1.0`:

| Approach | Detail |
|---|---|
| Document it in the README and changelog | "Skip 2.1.0 — see 2.1.1" |
| Move the `2.1.0` tag to point at the fix commit | Force-pushing tags is generally bad practice; only do this if you're confident no one has cached the broken commit |
| Bump to `2.1.1` and rely on consumers to update | The standard path. Old `2.1.0` stays on disk in their cache but is overwritten on next update |

## Backporting via release branches

When you maintain multiple major versions in parallel (`1.x` is in maintenance, `2.x` is current), use release branches in the plugin repo:

```
plugin-repo/
├── main                  ← active 2.x development
├── release/1.x           ← maintenance branch for 1.x
└── release/2.x           ← maintenance branch for 2.x
```

The flow when a fix needs to apply to both:

1. Fix on `main`, bump to `2.3.1`, tag `<plugin>--v2.3.1`
2. Cherry-pick the fix to `release/1.x`, bump that branch's `plugin.json` to `1.5.7`, tag `<plugin>--v1.5.7`
3. Push both tags

Consumers on `^1.0` get `1.5.7`; consumers on `^2.0` get `2.3.1`. The `<plugin>--v<version>` tag format keeps both lines distinct.

For the marketplace side, you may want to expose the maintenance line as a separate release channel — see [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md).

## Pre-release release loop

The full loop for shipping a release candidate:

```
edit → bump plugin.json to 2.0.0-rc.1 → commit → claude plugin tag --push
→ (test via a separate beta marketplace channel, or by depending on the pre-release from another plugin)
→ if good, bump to 2.0.0 → commit → claude plugin tag --push
→ if more iteration needed, bump to 2.0.0-rc.2 and repeat
```

A common pattern is to keep a `beta` branch on the marketplace that points at pre-release tags, alongside a `main` branch that points at stable tags. Consumers who want to try pre-releases add the marketplace at `#beta`. See [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md).

## Cleanup

| Concern | Handling |
|---|---|
| Pre-release tags accumulating | They're harmless; keep them for traceability or delete with `git tag -d` and a force push if needed |
| Old cache folders for pre-release versions | `~/.claude/plugins/cache/<mkt>/<plugin>/2.0.0-rc.1/` stays until uninstall or manual deletion |
| Switching between stable and pre-release on a consumer | Switch to the marketplace channel that points at the desired tag, then `/plugin update`. Old cache stays unless manually cleared |

## See also

- [`01_semver.md`](./01_semver.md) — pre-release exclusion rules in range matching
- [`02_tagging-convention.md`](./02_tagging-convention.md) — the `<plugin>--v<version>` tag format
- [`04_release-loop.md`](./04_release-loop.md) — the standard (non-pre-release) release flow
- [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md) — running a `beta` channel alongside `stable`
