# plugin-dev

End-to-end Claude Code plugin development toolkit.

> [!warning]
> **Work in progress.** This plugin is being authored. The skills, agents, commands, and tooling described in the project documentation aren't implemented yet — only the plugin scaffold exists at this point.

## Status

- [ ] Skills (lifecycle, dependencies, marketplace authoring, marketplace composition, extended capabilities, plugin config, persistent data, testing & benchmarking, publishing & releases, plugin CLI & UI)
- [ ] Vendored content from upstream `plugin-dev@claude-plugins-official` with `.upstream/manifest.json` provenance tracking
- [ ] Bin wrappers (status / sync / log / release / validate / bench)
- [ ] Specialist agents (marketplace-architect, dependency-auditor, release-manager)
- [ ] SessionStart hook (upstream staleness check)
- [ ] Scheduled background agent (weekly upstream-status report)

## Plan

See the documentation under [`docs/Claude Plugins/`](../../docs/Claude%20Plugins/) at the marketplace root for the full structural plan, the soft-fork-and-upstream-tracking pattern, and the dependency model this plugin will use.

## Installation (when complete)

Once published, install with:

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
/plugin install plugin-dev@sids-plugin-marketplace
```

## Provenance

This plugin will soft-fork content from the official Anthropic [`plugin-dev`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev) plugin (Apache 2.0) and extend it with the missing chapters. Upstream attribution and per-file provenance will live in `.upstream/manifest.json` once the soft-fork is performed.

## License

TBD — pending decision before first release.
