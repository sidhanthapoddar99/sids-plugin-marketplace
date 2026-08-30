---
name: project-setup
description: The single authority for how a repo is shaped — bootstrapping a new project, auditing or restructuring one, or any "where does this go" question. Owns the one repo tree (apps/, packages, data/, logs/), the three root env files + config.yaml, single-origin routing (Vite proxy, nginx edge), compose base + modifiers, the ctl entrypoint (dev, up, migrate, manage, gate), stack choices (FastAPI / Axum / Go; Vite / Next.js / Astro; Postgres / Redis / SQLite / Neo4j), frontend internals (tokens.css, a typography allowlist that OVERRIDES frontend-design, the api layer), backend internals (domain slices, serving, migrations), the security floor (captcha, rate limits, AI keys, prompt injection), production settings, the test ladder and conformance tests, and the AGENTS.md brief contract. Trigger on any mention of apps/, docker/, ctl, compose.base.yaml, .env.secrets, config.yaml, tokens.css, AGENTS.md, migrations, or a second frontend or backend, even mid-task. Skip pure in-file work; docs content is agent-ks.
---

# project-setup

One repo shape, one entrypoint, one origin. This skill decides where things go and how they connect, then hands the user a repo that `ctl` runs. It applies equally to a greenfield bootstrap and to a single "should this be a package?" question mid-task.

## Principles

1. One tree for every repo. `apps/` always, even for one app. A folder exists only when used.
2. One entrypoint: `ctl`. Nobody types `docker compose -f`. A rung of the gate is the same worker the dev verb runs.
3. One origin. The browser sees one host; prefixes separate pieces. A second origin only for a separate identity plane or a public SDK.
4. One value, one file, chosen by what it is: secret → `.env.secrets`, path → `.env.data`, host/port/prefix → `.env.proxy`, a backend default → `config.yaml`. No frontend env file. An unset `${VAR}` fails by name.
5. Base is prod. `compose.base.yaml` has no ports; modifiers add exposure. Paths are root-relative.
6. Promote when shared, never before. A scope imports only inward. Domains are ownership nouns.
7. Convergence is the design. Tokens and the stock scale; the typography allowlist in `AGENTS.md` overrides `frontend-design`.
8. Green means `ctl gate` passed. A check exits 0 only when the rule was proved.
9. Versions are `<version>` until resolved with the user. Never from memory.
10. The brief is the contract. Every chosen variant, exception and deferral is recorded in `AGENTS.md`; audits compare against it.

## The pages

Read the page that owns the question. Each page states the rule and points at `template/` for the code; it never repeats the code.

| Question | Page |
|---|---|
| Where does it go | `references/01_layout.md` |
| How is it configured | `references/02_env.md` |
| How does traffic reach it | `references/03_routing.md` |
| What do we pick | `references/04_stack.md` |
| How is a frontend built | `references/05_frontend.md` |
| How is a backend built | `references/06_backend.md` |
| What must be safe | `references/07_security.md` |
| What do I type | `references/08_ctl.md` |
| What makes it prod | `references/09_production.md` |
| What is green | `references/10_testing.md` |
| What holds everywhere; how to audit | `references/11_conventions.md` |

`template/` is a complete instance of the tree. `ctl`, `scripts/`, `docker/`, the env templates, `AGENTS.md` and the conformance test are real and run. The app folders under `apps/` are shape only: each file's comment states what it holds, and the code is written per project. Copy it, delete what the product does not need, rename `example-*` folders to role names. `template/ctl --help` is the verb list.

## Bootstrapping

Ask in two small batches, defaults flagged, then confirm before writing anything.

**Batch 1 — the product.** What it is, in one sentence. One repo or several (a part earns its own repo only for an independent release cadence that is real today, external consumers, or a visibility boundary). Deployed application or published package. Sibling repos this one expects (docs, an SDK it consumes). Docs: in-repo, a docs repo, or none. Open source or private.

**Batch 2 — the pieces.** Backends: how many, which language each, what they coordinate through. Does any surface need its own identity plane (operator vs user — a different look is not a yes). Frontends: how many, which kind each; theme both modes or light only; any non-web surface (desktop, mobile, PWA). Data engines from the requirement. External pieces that already exist (a hosted Postgres, a host proxy). ML or app, when Python is present. Anything that touches an LLM. The protection tier per public app.

Never assume, always ask: deployed vs distributed, sibling repos, identity planes, ML vs app, external services, OSS vs private, theming, versions.

**Confirm.** Restate what you heard as 5–10 bullets and get a yes. Then: copy `template/`, delete, rename, resolve every `<version>` with the user, fill `AGENTS.md` (recorded choices, skeletons, styling allowlist, exceptions), run `ctl setup` and `ctl check`, and end with `ctl --help` and the manual path in the README.

## Auditing

Follow the order in `references/11_conventions.md` § Audit order; stop at the first failing layer. Run `ctl check` first for the mechanical part. Report a table: file, rule broken, fix. A recorded choice or a recorded deferral in `AGENTS.md` is not a finding. Never read a filled `.env.*`; read the templates.

## A single question mid-task

Find the page from the table above, answer from it, and point at the template path that shows it. If the answer changes a recorded choice, say so and record it. If no page covers it, resolve from the principles and write the decision into `AGENTS.md`; never improvise a pattern inline.

## Out of scope

Training loops, remote GPUs and model serving: not covered; decide per project and record in `AGENTS.md`. Docs-site content: `agent-ks`. Host proxies and TLS (Traefik, certbot): outside the repo, mentioned only where the edge meets them.
