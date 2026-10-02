# Changelog

## 0.12.1

- Require direct copying of the CTL template instead of recreating equivalent implementations.
- Add copy commands, safe adaptation guidance for existing repos, and a review of differences against the template before completion.

## 0.12.0

- Add `ctl clean rust [--dry-run]` to remove local Rust debug builds and managed Rust development logs while preserving release builds, lockfiles, data and shared caches.

## 0.11.2

- Use `AGENTS.md` as the project brief without creating a template `CLAUDE.md`.
- Guide existing projects to migrate unique `CLAUDE.md` instructions before removal, and flag a root `CLAUDE.md` in `ctl check`.

## 0.11.1

- Document reusable internal container ports separately from configurable host development ports.
- Add a commented optional beta API address block and matching web-edge Compose wiring example.

## 0.11.0

- Consolidate database engines and migration jobs into the base Compose config; select development services through the dev preset with loopback database exposure.
- Replace development Nginx with native frontend proxies and rewrites; remove the separate db/dev Compose configs and development-proxy settings.
- Add routing and Compose regressions, including live Vite HTTP, WebSocket and HMR checks.

## 0.10.1

- Configure the Flyway migration directory explicitly and copy SQL files to `/migrations` inside the container, avoiding the default-folder deprecation warning.

## 0.10.0

- Add `ctl stop` and a read-only `--dry-run`: stop owned host groups and frozen servers before project containers, retaining containers and data.
- Verify shutdown, allow graceful watcher cleanup, reject unsafe process ownership, and report incomplete host or Docker shutdown.
- Add shared controller locks and a TypeScript/Watchexec Rust development example.
- Standardize PostgreSQL migrations on containerized Flyway with startup ordering and CTL commands.
- Validate development configuration and synchronize dependencies before startup, sharing the setup helpers.
- Add an optional shared-WASM document-engine example under `references/examples/`.
