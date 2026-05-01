# Managed marketplace restrictions

`strictKnownMarketplaces` is a managed-settings-only key that restricts which marketplaces users can add. It enforces an organisation policy that overrides anything in user or project settings.

> Lives only in **managed settings** — the OS-specific managed-settings location an admin deploys to fleet machines. Setting it in user or project `settings.json` has no effect.

## Modes

| Value | Behaviour |
|---|---|
| `[]` (empty array) | **Full lockdown.** Users cannot add any marketplaces. Only marketplaces pre-installed via managed settings or pre-existing user settings can be used |
| `[<source>, ...]` (non-empty array) | **Allowlist.** Users can only add marketplaces matching one of the listed source patterns |
| Field absent | No restriction. Users can add any marketplace |

There is no explicit "denylist" mode — the allowlist semantics implicitly deny anything not matching.

## Allowlist entry shape

Each entry in the allowlist describes a pattern. Users adding a marketplace whose source matches any one entry is permitted; mismatches are rejected with an `unauthorized-marketplace` error.

```json
{
  "strictKnownMarketplaces": [
    {
      "source": "github",
      "repo": "your-org/*"
    },
    {
      "source": "url",
      "hostPattern": "^gitlab\\.internal$"
    },
    {
      "source": "github",
      "repo": "anthropics/claude-plugins-official"
    }
  ]
}
```

| Field | Notes |
|---|---|
| `source` | Match the source-type discriminator: `github`, `url`, `git-subdir`, `npm`, or relative-path forms |
| `repo` | For `github`: `owner/name` or `owner/*` glob |
| `hostPattern` | For `url` / `git-subdir`: regex against the host portion of the URL |
| `pathPattern` | For `url` / `git-subdir`: regex against the path portion |
| `package` | For `npm`: package name or scope glob (e.g. `@acme/*`) |
| `registry` | For `npm`: regex against the registry URL |

A request matches an entry when `source` matches and all the field-specific patterns on that entry match. Patterns are anchored: use explicit `^…$` if you want exact-match.

## Common allowlist recipes

### Lock to one trusted org

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "your-org/*" }
  ]
}
```

Only `your-org/*` GitHub repos can be added as marketplaces.

### Lock to internal Git plus the official Anthropic marketplace

```json
{
  "strictKnownMarketplaces": [
    { "source": "url", "hostPattern": "^git\\.internal\\.acme\\.corp$" },
    { "source": "github", "repo": "anthropics/claude-plugins-official" }
  ]
}
```

### Full lockdown (no new marketplaces at all)

```json
{
  "strictKnownMarketplaces": []
}
```

Useful when the admin pre-installs every marketplace via managed settings and wants to prevent users adding anything else. Combine with managed-scope `extraKnownMarketplaces` to pre-register the allowed set.

### Allow only npm-distributed plugins from a private registry

```json
{
  "strictKnownMarketplaces": [
    {
      "source": "npm",
      "registry": "^https://npm\\.acme\\.corp/"
    }
  ]
}
```

## Interaction with other settings

| Setting | Scope | Interaction |
|---|---|---|
| `strictKnownMarketplaces` | Managed only | Final word. Overrides user/project additions |
| `extraKnownMarketplaces` | Project / user / managed | If a project recommends a marketplace not in the managed allowlist, the prompt is suppressed and the user can't accept it |
| `enabledPlugins` | Project / user | Only enables plugins from already-registered marketplaces; can't bypass `strictKnownMarketplaces` |
| User-scope manual `add` | n/a | Blocked at the `/plugin marketplace add` step if the source doesn't match the allowlist |

The error users see when blocked: `Marketplace source <X> is not permitted by managed settings.`

## Trust model in managed environments

Managed `strictKnownMarketplaces` is the enforcement layer for organisations that need plugin distribution to flow only through approved channels. The threat model:

- A user is tricked into running `/plugin marketplace add untrusted/repo` — blocked at the CLI layer
- A project's `extraKnownMarketplaces` recommends an unvetted marketplace — the prompt to add is suppressed
- A pre-existing user-scope marketplace remains usable, but new additions are gated

For the broader security context (plugins run unsandboxed at user privilege), see [`10_trust-and-security.md`](../10_trust-and-security.md).

## Where the file lives

Managed settings are deployed by an admin, not edited interactively. Per OS:

| OS | Path |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\ProgramData\ClaudeCode\managed-settings.json` |

For the full managed-settings layout, see [`Documentation/ClaudeSettings/`](../../ClaudeSettings/).

## See also

- [`06_extra-known-marketplaces.md`](./06_extra-known-marketplaces.md) — the discoverability counterpart for teams
- [`10_trust-and-security.md`](../10_trust-and-security.md) — broader trust model
- [`Documentation/ClaudeSettings/05_plugin-related-settings.md`](../../ClaudeSettings/05_plugin-related-settings.md) — full reference for plugin-related settings keys
