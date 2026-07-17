# MCP servers — where the code and config live

For a repo that ships or consumes a Model Context Protocol server. Owns the placement decisions: whether an MCP server is an app or a package, where its client config lives, the local-vs-remote transport call, and how the tool surface is versioned. It does not own MCP protocol internals — those are the SDK's job.

## Is the MCP server an app or a package?

Apply the app-vs-package test (`references/3-app/01-structure-and-stack/00_app-anatomy.md`):

| The server is… | It lives as | Where |
|---|---|---|
| run/deployed by you (a process you host) | an **app** | `apps/<name>-mcp/` |
| published for external hosts to install and run | a **package** | `packages/<name>-mcp/` (publishing → `references/2-repo/01-layouts/06_embeddable-package.md`) |

A deployed MCP server is an ordinary backend app — it gets the full every-app contract (own manifest, README, Dockerfile, tests). A published one is a distributable package with an export surface and semver.

## Where MCP client config lives

- **`.mcp.json` at the repo root** is the committed, project-scoped server list — the servers this repo's agents expect. Commit it so every contributor and CI agent gets the same tools.
- **Per-user / secret-bearing entries** (a personal token, a machine-local path) stay out of the committed file — reference an env var (`${VAR}` from the untracked `.env`, `references/2-repo/03-env-config/00_env-precedence.md`) rather than inlining the value. Committed config, injected secrets.

## Local stdio vs remote HTTP

| Transport | Use when |
|---|---|
| **local stdio** | the server runs on the same machine as the client (a CLI tool, a dev-box helper); simplest, no network surface |
| **remote HTTP** | the server is a shared/hosted service multiple clients reach; then it is a deployed app behind the normal edge — auth + rate limit + logging at the choke point (`references/3-app/09-security-hardening/01_rate-limiting.md`) |

A remote MCP server is public surface: it gets the same edge protection and audit posture as any other exposed app.

## Versioning the tool surface

The set of tools an MCP server exposes **is its contract**, exactly like an API. Adding a tool is additive; renaming or removing one, or changing a tool's input schema, is a breaking change — version it (semver on a published package; a documented version field on a deployed one) and coordinate with consumers. Pin third-party MCP servers you depend on to an exact version; an unpinned upstream can change the tool surface under you.

## Anti-patterns

- **Business logic in the MCP layer** — the server should call the app's existing service layer, not reimplement it. The MCP handler is a thin adapter over `service.py`, mirroring the router/service split (`references/4-feature/feature-folders.md`).
- **Unpinned third-party MCP servers** — a floating version silently changes the available tools.
- **Committing a token into `.mcp.json`** — reference an env var instead.
- **A single mega-tool** that takes a free-form command — expose discrete, typed tools, not an exec passthrough.
- **Treating a published MCP server as an app** (or a hosted one as a package) — run the app-vs-package test.

## See also

- `references/3-app/01-structure-and-stack/00_app-anatomy.md` — the app-vs-package test
- `references/3-app/08-ai/01_agent-sdks.md` — LLM/agent integration inside an app
- `references/3-app/08-ai/02_ai-keys-and-safety.md` — key usage + prompt-injection posture for tool-calling
- `references/2-repo/01-layouts/06_embeddable-package.md` — publishing a distributable MCP package
- `references/2-repo/03-env-config/00_env-precedence.md` — env injection for config secrets
