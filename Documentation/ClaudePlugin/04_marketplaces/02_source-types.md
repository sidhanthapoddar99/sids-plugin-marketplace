# Plugin source types

The `source` field on a plugin entry tells Claude Code where to fetch the plugin from. It accepts one of five forms — one bare-string form for in-repo plugins, and four object forms for remote ones. Object forms always carry a `source` discriminator key.

## Quick reference

| Form | Shape | Use for |
|---|---|---|
| Relative path | `"./plugins/foo"` (string, must start with `./`) | Plugin in the same repo as the marketplace |
| `github` | `{"source": "github", "repo": "owner/name", "ref?": "...", "sha?": "..."}` | Plugin in another GitHub repo |
| `url` | `{"source": "url", "url": "https://...", "ref?": "...", "sha?": "..."}` | Plugin on a non-GitHub git host (GitLab, Bitbucket, Azure DevOps, AWS CodeCommit, internal Gerrit) |
| `git-subdir` | `{"source": "git-subdir", "url": "...", "path": "tools/plugin", "ref?": "...", "sha?": "..."}` | Plugin in a subdirectory of a monorepo (sparse clone) |
| `npm` | `{"source": "npm", "package": "@org/name", "version?": "^2.0.0", "registry?": "..."}` | Plugin distributed as an npm package |

## 1. Relative path

```json
{ "name": "my-plugin", "source": "./plugins/my-plugin" }
```

Resolves relative to the marketplace root (the directory containing `.claude-plugin/`), regardless of where `marketplace.json` itself lives. The `./` prefix is required unless `metadata.pluginRoot` is set:

```json
{
  "metadata": { "pluginRoot": "./plugins" },
  "plugins": [
    { "name": "formatter", "source": "formatter" }
  ]
}
```

> **Caveat.** Relative paths only work for marketplaces added via Git or local directory. They do **not** resolve when a marketplace is added via a static URL pointing at `marketplace.json` directly — in that case only the JSON file is downloaded, not the surrounding repo. Use `github`/`url`/`npm` for URL-distributed marketplaces.

> **`file://` URLs are rejected.** `/plugin marketplace add file:///path/...` errors with `"Invalid marketplace source format. Try: owner/repo, https://..., or ./path"`. Use a relative or absolute filesystem path (e.g. `./marketplace` or `/abs/path/marketplace`) for local-directory marketplaces.

## 2. `github`

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

| Field | Required | Notes |
|---|---|---|
| `repo` | yes | `owner/repo` form |
| `ref` | no | Branch or tag (defaults to repository default branch) |
| `sha` | no | Full 40-character commit SHA for exact pinning |

## 3. `url` (any git URL)

For non-GitHub hosts. The `.git` suffix is optional.

```json
{
  "name": "internal-lint",
  "source": {
    "source": "url",
    "url": "https://gitlab.com/team/internal-lint.git",
    "ref": "main"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `url` | yes | Full git URL (`https://` or `git@`) |
| `ref` | no | Branch or tag |
| `sha` | no | Full 40-char commit SHA |

Works with GitLab, Bitbucket, Azure DevOps, AWS CodeCommit, internal Gerrit, anything Claude Code can `git clone`. CLI uses your local Git auth.

## 4. `git-subdir`

Plugin lives in a subdirectory of a (typically monorepo) git repo. Claude Code performs a sparse, partial clone — only the named subdirectory is fetched.

```json
{
  "name": "ci-helpers",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/acme/monorepo.git",
    "path": "tools/ci-helpers",
    "ref": "v2.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `url` | yes | Git URL, GitHub `owner/repo` shorthand, or SSH URL |
| `path` | yes | Subdirectory containing the plugin |
| `ref` | no | Branch or tag |
| `sha` | no | Full commit SHA |

## 5. `npm`

```json
{
  "name": "registry-plugin",
  "source": {
    "source": "npm",
    "package": "@acme/claude-plugin",
    "version": "^2.0.0",
    "registry": "https://npm.example.com"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `package` | yes | Package name (scoped or unscoped) |
| `version` | no | Exact version or semver range (`2.1.0`, `^2.0.0`, `~1.5.0`) |
| `registry` | no | Custom registry URL (default: system npm registry) |

> Tag-based dependency resolution does **not** apply to npm sources — see [`09_versioning-and-publishing/03_version-resolution.md`](../09_versioning-and-publishing/03_version-resolution.md). Constraints are still checked at load time; mismatched npm versions surface as `dependency-version-unsatisfied`.

## Optional `ref` and `sha` on git-based sources

`github`, `url`, and `git-subdir` all accept:

- `ref` — branch or tag (defaults to repository default branch)
- `sha` — full 40-character commit SHA for exact pinning

The plugin's `ref`/`sha` is **independent** of the marketplace's own ref. A marketplace at `acme/catalog#v1.0.0` can list a plugin at `acme/formatter#v2.3.0` — the marketplace and the plugin track different versions. See [`03_ref-and-sha-pinning.md`](./03_ref-and-sha-pinning.md).

## See also

- [`03_ref-and-sha-pinning.md`](./03_ref-and-sha-pinning.md) — what `ref` vs `sha` mean and when to use each
- [`05_catalogue-pattern.md`](./05_catalogue-pattern.md) — building a marketplace from `github` / `url` / `npm` entries
- [`09_versioning-and-publishing/03_version-resolution.md`](../09_versioning-and-publishing/03_version-resolution.md) — how the resolved version interacts with the source
