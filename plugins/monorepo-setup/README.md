# monorepo-setup

Personal monorepo bootstrapping and convention plugin, encoded so Claude follows them automatically when initializing or working in a project.

> [!warning]
> **Work in progress.** This plugin is being authored. Skills, scripts, and templates aren't filled in yet — only the scaffold exists.

## Purpose

When starting a new project (or working inside an existing one), Claude should follow established personal conventions for layout, configuration, and tooling rather than inventing fresh patterns each time. This plugin captures those conventions and teaches Claude to apply them.

The intent is monorepo-friendly: most projects live under one repo with multiple services/apps that share infrastructure, so the conventions reflect that.

## Topics this plugin will cover

- [ ] **Project initialization** — directory layout, what files to create on day one, monorepo vs single-package decisions
- [ ] **Environment variables** — `.env` / `.env.local` / `.env.example` structure, naming conventions, where each variable belongs
- [ ] **Config files** — `pyproject.toml` / `package.json` / `tsconfig.json` layout, shared base configs in a monorepo
- [ ] **Docker Compose** — service organization, profiles, override files, how dev/test/prod compose files relate
- [ ] **Run scripts** — convention for `scripts/` (or `bin/`, or `Makefile`), how to invoke compose stacks, common helper scripts
- [ ] **Database / Alembic** — migration layout, naming, when to autogenerate vs hand-write, env-driven connection strings, multi-tenant or multi-schema patterns
- [ ] **Secrets management** — local secrets (`.env.local`, gitignored), shared dev secrets (1Password / Vault / etc.), CI secrets, what is allowed to leak vs what must rotate
- [ ] **Monorepo conventions** — workspace layout (`apps/`, `packages/`, `services/`, `infra/`), shared dependencies, build orchestration (turborepo / nx / pnpm workspaces / uv workspaces), cross-package imports

## What gets shipped

Likely capabilities the plugin will expose (TBD as the conventions get filled in):

- **Skills** — one per topic above, triggered when Claude works in or initializes a project
- **Slash commands** — e.g. `/ms-init` to bootstrap a new project, `/ms-add-service` to add a new service to a monorepo
- **`bin/` wrappers** — helper scripts (compose-up, compose-down, db-migrate, etc.) auto-added to `$PATH`
- **Templates** — `assets/` containing starter `pyproject.toml`, `docker-compose.yml`, `.env.example`, etc. that commands copy in

## Installation (when complete)

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
/plugin install monorepo-setup@sids-plugin-marketplace
```

## License

TBD — pending decision before first release.



