# Ref and SHA pinning

There are two independent layers of pinning: the **marketplace** ref (which version of `marketplace.json` Claude Code reads) and the **plugin source** ref/sha (which version of each plugin gets fetched). They are unrelated — a marketplace pinned to one tag can still list plugins pinned to other tags or floating on `main`.

## Marketplace pin: `#<ref>` on the URL

When adding a Git-backed marketplace, append `#<branch-or-tag>` to the URL:

```
/plugin marketplace add https://gitlab.com/team/plugins.git#v1.0.0
/plugin marketplace add owner/repo#stable
/plugin marketplace add git@github.com:org/marketplace.git#release-2026
```

The `#<ref>` is what gets fetched when Claude Code reads `marketplace.json`. To track the latest, omit `#<ref>` — Claude Code uses the repo's default branch.

> The marketplace pin uses **`#`**, not `@`. The `@` syntax (`<plugin>@<marketplace>`) refers to the marketplace *name*, not a ref.

The marketplace pin only supports `ref` (branch or tag). There is no `sha`-level pin at the marketplace add stage; for immutable marketplace pinning, point at a tag and don't move the tag.

To refresh: `/plugin marketplace update <name>`. To list configured marketplaces: `/plugin marketplace list`.

## Plugin source pin: `ref` and `sha` fields

Inside `marketplace.json`, each git-based plugin source (`github`, `url`, `git-subdir`) accepts both a `ref` and an optional `sha`:

```json
{
  "name": "deploy-tools",
  "source": {
    "source": "github",
    "repo": "acme/deploy-tools",
    "ref": "v2.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

| Field | Mutability | Use when |
|---|---|---|
| `ref` | Mutable — points at a branch or tag that can be moved | You want consumers to pick up the latest content under a moving label (`main`, `stable`) |
| `sha` | Immutable — exact 40-character commit hash | You want the install to be byte-for-byte reproducible regardless of upstream changes |

You can supply both. With both set, `sha` is the authoritative target; `ref` becomes a hint Claude Code uses for cache naming and display purposes.

Omitting both leaves the source on the repository's default branch — fine for in-flight development, but downstream consumers see new content on every push without a version bump.

## Independence: marketplace ref vs plugin ref

The two pin layers are orthogonal. Examples of valid combinations:

| Marketplace add | Plugin source `ref` | Effect |
|---|---|---|
| `acme/catalog` (default branch) | `v1.2.0` | Marketplace tracks latest, plugin pinned to a tag |
| `acme/catalog#release-2026` | (omitted) | Marketplace pinned to a release branch, plugin tracks its own default branch |
| `acme/catalog#v3.0` | `v3.0` (matching) | Both pinned together — coordinated release |
| `acme/catalog#main` | `sha: a1b2c3...` | Marketplace floats on main, plugin frozen to a specific commit |

This independence is what enables [release channels](./04_release-channels.md): two marketplace refs can list the same plugin at different ref/sha values to expose stable vs. latest tracks.

## Cache identity and version resolution

The plugin source pin doesn't directly determine the version label. Version resolution still follows the order in [`09_versioning-and-publishing/03_version-resolution.md`](../09_versioning-and-publishing/03_version-resolution.md):

1. `version` in the plugin's `plugin.json`
2. `version` in the marketplace entry
3. Git commit SHA of the source (the SHA the `ref`/`sha` resolve to)
4. `unknown` for npm sources without a version, or local non-git sources

So pinning by `sha` doesn't override an explicit `version` in `plugin.json`; it just guarantees which commit's content gets cached.

## Choosing between `ref` and `sha`

| Situation | Pin with |
|---|---|
| Following a release tag | `ref: "v2.0.0"` |
| Tracking a release branch | `ref: "release-2026"` |
| Reproducing an audit-stable install | `sha: "<full 40-char>"` |
| In-flight development against `main` | omit both |
| Soft-fork tracking an upstream commit | `sha` (the `.upstream/manifest.json` records the same SHA) |

For published marketplaces with versioned plugins, `ref` pointing at a tag is the common case. `sha` pinning is most useful when the plugin repo's tag could be moved or force-pushed and you need protection against that.

## See also

- [`02_source-types.md`](./02_source-types.md) — which source types accept `ref`/`sha`
- [`04_release-channels.md`](./04_release-channels.md) — using two marketplace refs to expose two release channels
- [`09_versioning-and-publishing/02_tagging-convention.md`](../09_versioning-and-publishing/02_tagging-convention.md) — the `<plugin>--v<version>` tag format that `ref` typically points at
