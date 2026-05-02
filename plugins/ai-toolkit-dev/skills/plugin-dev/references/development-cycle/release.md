# Cutting a release

How to publish a new version of a plugin so users can install it predictably.

## The release model

Two coupled artifacts:

1. **The plugin's git tag** — `<plugin-name>--v<X.Y.Z>`. Created by `claude plugin tag`. This is what `version`-pinned dependents resolve to.
2. **The marketplace's `marketplace.json`** — its plugin entry's `version` field, if pinned, points at #1. The marketplace ref also has a tag.

Bumping a plugin without bumping the marketplace ref means consumers tracking the marketplace don't see the new version (unless they didn't pin and are tracking marketplace HEAD, in which case they will).

## Single-plugin release in a self-hosted marketplace

Repo layout:

```
my-marketplace/
├── .claude-plugin/marketplace.json
└── plugins/
    └── my-plugin/
        ├── .claude-plugin/plugin.json
        └── ...
```

Steps:

```bash
cd plugins/my-plugin

# 1. Edit code, commit changes
git add .
git commit -m "feat: add foo handling"

# 2. Bump version in plugin.json by hand, then tag
$EDITOR .claude-plugin/plugin.json         # set "version": "1.3.0"
git add .claude-plugin/plugin.json && git commit -m "chore: bump version to 1.3.0"
claude plugin tag                          # auto-derives the tag from plugin.json + marketplace entry

# 3. Pin in marketplace.json
cd ../..
jq '.plugins[] |= if .name == "my-plugin" then .version = "1.3.0" else . end' \
  .claude-plugin/marketplace.json | sponge .claude-plugin/marketplace.json
git add .claude-plugin/marketplace.json
git commit -m "chore: pin my-plugin@1.3.0"

# 4. Push (both the marketplace commit and the plugin tag)
git push
git push --tags

# 5. Consumer-side
claude plugin marketplace update sids-plugin-marketplace
claude plugin install my-plugin             # picks up 1.3.0
```

Step 3 is what makes the marketplace authoritative for the version. Skip it if you're fine with consumers always tracking HEAD.

## Multi-plugin marketplace release

If you bumped multiple plugins in one batch, do step 3 per plugin:

```bash
for plugin in plugin-a plugin-b; do
  cd plugins/$plugin
  $EDITOR .claude-plugin/plugin.json     # bump "version" by hand
  git add .claude-plugin/plugin.json && git commit -m "chore($plugin): bump"
  claude plugin tag --push               # tag derives from plugin.json
  cd ../..
done

# Update marketplace.json with all new versions
# (jq script that maps plugin names to their just-tagged versions)
```

## Version resolution order at install

When a consumer runs `claude plugin install <plugin>`:

1. **Plugin entry has `version: X.Y.Z` and `strict: true`** → resolve to tag `<plugin-name>--v<X.Y.Z>` exactly. Fail if missing.
2. **Plugin entry has `version: X.Y.Z`** without `strict` → prefer exact tag; fall back to highest tag matching the SemVer range expressed by `X.Y.Z` (e.g. `1.2.3` → `^1.2.3`).
3. **Plugin entry has no `version` field** → use the marketplace ref's HEAD content for that plugin (whatever's at `plugins/<plugin>/` right now in the marketplace repo).

For dependents:
- A `dependencies[]` entry with `version: "^1.0"` resolves the same way: scan tags `<dep>--v*`, pick the highest matching `^1.0`.

## Tagging conventions

`claude plugin tag` (run from inside a plugin folder) creates the tag `<plugin-name>--v<X.Y.Z>` — auto-derived from the plugin's `plugin.json` `version` field and its marketplace entry. The double-dash + `v` prefix is required — it disambiguates plugin tags in monorepos where one repo hosts multiple plugins (each with their own version stream). Useful flags: `--push` (push to remote after creating), `--dry-run` (print without creating), `-f/--force` (override dirty tree or existing tag).

Manual tagging without `claude plugin tag` is fine as long as the format matches:

```bash
git tag my-plugin--v1.2.3
git push origin my-plugin--v1.2.3
```

## Pre-release tags

Pre-release versions follow SemVer:

```
my-plugin--v1.2.3-rc.1
my-plugin--v1.2.3-beta.2
my-plugin--v2.0.0-alpha
```

By default, semver ranges in `dependencies` exclude pre-releases (e.g. `^2.0.0` will NOT match `2.0.0-rc.1`). To opt in, declare the dependency range with an explicit pre-release suffix (`^2.0.0-0` or `>=2.0.0-rc`).

There is no `--version` flag on `claude plugin install`. To distribute a pre-release to consumers, either pin the marketplace entry's `version` to the pre-release tag or expose pre-releases on a separate marketplace channel (a `beta` branch alongside `main`). See the docs `04_marketplaces/04_release-channels.md`.

## Release checklist

For a public release:

1. Plugin loads cleanly (`claude plugin list --json | jq '.errors'` returns empty for this plugin; `/doctor` reports no health issues)
2. Clean-install loop passes (see `troubleshooting.md`, Part 1)
3. Headless smoke test passes (see `testing.md`)
4. CHANGELOG.md updated with the new version
5. Bump `version` in `plugin.json` then `claude plugin tag --push`
6. Marketplace `marketplace.json` updated with the new version
7. Marketplace ref bumped + pushed
8. Verify via consumer-side install

For a personal plugin you only use yourself, steps 4 and 8 are optional.

## Hotfixes and yanking

There's no formal "yank" mechanism. To pull a bad release:

1. Bump `version` in `plugin.json` again with the fix, commit, then `claude plugin tag --push`
2. Update the marketplace pin to the new version
3. Push

Anyone who already installed the bad version still has it cached and enabled. They'll pick up the fix on the next `claude plugin marketplace update` + `install`.

If the bad release was actively dangerous (e.g. data corruption), the fix should include a SessionStart migration script that detects and repairs.

## Backporting

For plugins with multiple supported major versions, you can maintain release branches:

```
git checkout -b release/v1.x main
git cherry-pick <hotfix-commit>
$EDITOR .claude-plugin/plugin.json    # set version to "1.4.5"
git add . && git commit -m "chore: bump 1.4.5"
claude plugin tag --push
```

Then in the marketplace, pin separate plugin entries (with different `name`s if you want both major versions installable side-by-side, or just the latest at the existing entry).
