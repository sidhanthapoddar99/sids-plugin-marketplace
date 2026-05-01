# Release channels

Because the marketplace ref and the plugin source ref are independent, you can run **two marketplaces** that point at the same plugin repos but resolve those plugins at different versions. This gives consumers a stable channel and a latest channel from the same upstream.

## The pattern

A single Git repo hosting `marketplace.json` can be added by consumers under two different refs:

```
/plugin marketplace add acme/plugins#stable
/plugin marketplace add acme/plugins#latest
```

The `stable` and `latest` branches each contain a `marketplace.json` whose plugin entries differ only in `ref` (or `sha`):

**`stable` branch — `marketplace.json`:**
```json
{
  "name": "acme-plugins-stable",
  "owner": { "name": "Acme" },
  "plugins": [
    {
      "name": "deploy-tools",
      "source": {
        "source": "github",
        "repo": "acme/deploy-tools",
        "ref": "v2.0.0"
      }
    }
  ]
}
```

**`latest` branch — `marketplace.json`:**
```json
{
  "name": "acme-plugins-latest",
  "owner": { "name": "Acme" },
  "plugins": [
    {
      "name": "deploy-tools",
      "source": {
        "source": "github",
        "repo": "acme/deploy-tools",
        "ref": "main"
      }
    }
  ]
}
```

Consumers pick a channel by which ref they add. They can have both installed simultaneously — they'd be two different marketplace registrations and (typically) two different plugin installs since the `name` differs.

## Channel naming

The marketplace `name` should differ between channels. Consumers reference plugins as `<plugin>@<marketplace>`, and if both channels claim the same marketplace name, registering the second one will conflict with the first.

Common naming patterns:

| Channel | `name` |
|---|---|
| Stable | `acme-plugins-stable`, `acme-plugins`, `acme-stable` |
| Latest | `acme-plugins-latest`, `acme-plugins-edge`, `acme-latest` |
| Beta / RC | `acme-plugins-beta`, `acme-plugins-rc` |
| LTS | `acme-plugins-2026-lts` |

## Resolution rule: different refs, same version, treated identical

There's a wrinkle: if two refs in your marketplace point to **commits that resolve to the same plugin version string**, Claude Code treats them as identical for caching purposes. This is because the version label drives the cache folder name, not the ref.

Example: if the `stable` branch lists `deploy-tools` at `ref: "v2.0.0"` and the `latest` branch lists it at `ref: "main"`, but `main` happens to currently point at the same commit as `v2.0.0` — both resolve to version `2.0.0`, both cache to `~/.claude/plugins/cache/<mkt>/deploy-tools/2.0.0/`. They're effectively the same install.

To make channels diverge, ensure each channel resolves to a different version. Two ways:

| Approach | How |
|---|---|
| Set `version` per channel | Each channel's `marketplace.json` overrides with a different `version` value on the plugin entry |
| Pin to refs that resolve to different commits | The plugin's own `plugin.json` carries different versions on those commits (e.g. `main` is `2.1.0-dev`, `v2.0.0` is `2.0.0`) |

The cleaner approach is the second: let the plugin's `plugin.json` be the source of truth, and ensure the refs you pin in each channel point at commits where `plugin.json`'s `version` differs.

## Maintaining channels

The maintenance loop for a stable + latest setup:

1. Develop on `main` of the plugin repo
2. When ready, tag a release using the [`<plugin>--v<X.Y.Z>` convention](../09_versioning-and-publishing/02_tagging-convention.md)
3. Update the `stable` branch of the marketplace repo to point its plugin entries at the new tag
4. Push `stable`
5. The `latest` branch's plugin entries already point at `main`; they pick up new content automatically

Consumers on `stable` get the bump on their next `/plugin update`. Consumers on `latest` get every commit on `main` (within the version-resolution rules above).

## Channel use cases

| Use case | Channels |
|---|---|
| Internal team running production tooling | `stable` (pinned tags) + `dev` (main) for the platform team's own use |
| Open-source plugin with eager and conservative users | `stable` + `latest` |
| LTS support for long-running deployments | `2026-lts` branch frozen to that year's last patch series |
| Pre-release testing | `beta` channel pointing at `-rc` tags; see [`09_versioning-and-publishing/05_pre-releases-and-hotfixes.md`](../09_versioning-and-publishing/05_pre-releases-and-hotfixes.md) |

## See also

- [`03_ref-and-sha-pinning.md`](./03_ref-and-sha-pinning.md) — the independence of marketplace ref and plugin ref
- [`09_versioning-and-publishing/04_release-loop.md`](../09_versioning-and-publishing/04_release-loop.md) — the standard release loop for one channel
- [`09_versioning-and-publishing/05_pre-releases-and-hotfixes.md`](../09_versioning-and-publishing/05_pre-releases-and-hotfixes.md) — pre-release tags and hotfix backports
