---
name: project-setup
description: Use this skill for how a repo is shaped: bootstrapping a new project, auditing or restructuring one, or a "where does this go" question mid-task in a repo built this way. It owns the tree (apps/, apps/packages/, data/, logs/), the three root env files and config.yaml, single-origin routing (Vite proxy, nginx edge), docker/ compose configs plus modifiers, service subsets and presets, the ctl entrypoint (dev, up, up preset, db migrate, manage, gate), stack choice (FastAPI / Axum / Go; Vite / Next.js / Astro; Postgres / Redis / SQLite / Neo4j), the frontend folder shape (a routing folder, layout/, modules/, components/, lib/, for Vite with TanStack Router and for Next.js), tokens.css and a typography allowlist that beats frontend-design once tokens exist, where migrations live, the security floor (captcha, rate limits), the gate ladder (a four-rung floor, the rest opt-in), the review passes, the add-ons (git hooks, memory/, e2e), and what AGENTS.md records. Trigger on any of those names, or on a second frontend or backend, even mid-task. Skip work inside one file, including a migration's SQL; docs content is agent-ks; instruction wording is instruction-writing; Kubernetes and cloud deploy targets are out of scope.
---

# project-setup

One repo shape, one entrypoint, one origin. This skill decides where things go and how they connect. It answers three kinds of request with the same rules: a bootstrap, an audit, and a single question mid-task. The rules live in the fifteen pages under `references/`. This file is the workflow and the map.

## Before anything

1. Read `AGENTS.md` at the repo root when it exists. It records the choices this repo has already made, and a recorded choice is never a finding.
2. Find the page that owns the question in the table below. Read that page, not the set, because each page owns one question and the set is about 1,300 lines.
3. Point at `template/` for the code. A page states a rule and names the template path that shows it. It never repeats the code, so the code has one home.
4. Treat `additional-template/` as opt-in. It holds the add-ons: git hooks, `memory/`, a browser suite. Its `README.md` says when each is usually earned. Install one only when the user asks. Recommend one with its reason, then wait. The same holds for a ladder rung beyond the four-rung floor.

## The pages

| Question | Page |
|---|---|
| Where does it go | `references/01_layout.md` |
| How is it configured | `references/02_env.md` |
| How does traffic reach it | `references/03_routing.md` |
| Add a second backend | `references/03_routing.md`, case 5 |
| Add a second or third frontend | `references/03_routing.md`, case 3 |
| What do we pick | `references/04_stack.md` |
| How is a frontend built | `references/05_frontend.md` |
| How is a backend built | `references/06_backend.md` |
| What must be safe | `references/07_security.md` |
| What do I type | `references/08_ctl.md` |
| How `ctl up` assembles a stack: configs, modifiers, services, presets, include | `references/08a_ctl_docker.md` |
| What makes it prod | `references/09_production.md` |
| How HTTP exposure and TLS are configured | `references/12_http-and-tls.md` |
| What a person reviews by hand | `references/10a_review.md` |
| What is green; the ladder; the static rungs | `references/10b_static-checks.md` |
| Where tests live; the dynamic rungs | `references/10c_dynamic-tests.md` |
| What holds everywhere; the audit order | `references/11_conventions.md` |

`template/` is the floor of the tree. `ctl`, `scripts/`, `docker/`, the env templates and `AGENTS.md` are real and run. `additional-template/` holds the add-ons at the same relative paths; they are real too, and a repo gets them one at a time on the user's word. The app folders under `apps/` are shape only: each file's comment states what it holds, and the code is written per project. A page may name a file the template does not carry, such as `gunicorn.conf.py`, `lib/theme.ts` or `alembic_helpers.py`. Those are written per project too. `template/ctl --help` is the verb list.

For changes to ctl’s environment loader, run the [ctl tooling tests](tests/ctl/README.md).

## Principles

The fallback for a question no page covers. Each line points at the page that owns the rule, so the rule has one home and this list stays short.

1. **One tree for every repo** (`01_layout.md`). A repo with one app and one with five look the same from the root, so nothing is re-decided when the second app arrives.
2. **One entrypoint, `ctl`** (`08_ctl.md`). A worker is a script under `scripts/` that one verb runs; a rung is one step of `ctl gate`. A rung calls the same worker the dev verb calls, so the check and the loop cannot drift.
3. **One origin** (`03_routing.md`). The browser sees one host and prefixes separate the pieces, so there is no CORS and no URL in a bundle.
4. **One value, one file, chosen by what it is** (`02_env.md`). Secret, path, route or backend default each have one file, so a key is found by its kind and `ctl check` can test the file by its key names.
5. **Base is prod** (`08a_ctl_docker.md`, `09_production.md`). A config (`compose.<name>.yaml`, `base` is the whole stack) has no ports and modifiers add exposure, because compose lists only union, so exposure can only be added, never removed.
6. **Promote when shared, never before** (`11_conventions.md`). A thing moves up a scope at its second consumer, because a premature package is a second manifest to keep green for nothing.
7. **Convergence is the design** (`05_frontend.md`). Tokens and a typography allowlist in `AGENTS.md` override `frontend-design` once they exist, because a bold new look on every page is drift, not design.
8. **Green means `ctl gate` passed** (`10b_static-checks.md`). A check exits 0 only when the rule was proved, so green never means "nothing ran". The floor is four rungs that cost seconds; every further rung, hook and suite is the user's call, because a prototype pays for each on every commit.
9. **Versions are `<version>` until resolved with the user** (`04_stack.md`). A version from memory is a guess that installs, so `ctl check` names every placeholder and `ctl setup` refuses to install while one remains.
10. **The brief is the contract** (`11_conventions.md`). Every chosen variant, exception and deferral is recorded in `AGENTS.md`, because the skill is not always loaded and the brief is, and an audit compares against the brief.

## When you run this skill

- Decide and keep going: which page answers, the wording of a finding, the order in which you copy and delete.
- Decide and record in `AGENTS.md`: a structural choice a page leaves open, and any exception to the tree. An unrecorded choice reads as drift at the next audit.
- Never on your own: an add-on from `additional-template/`, or a ladder rung beyond `lint typecheck test check`. A recommendation is welcome; the install waits for the user's yes.
- Stop and ask: a bootstrap question below whose answer is not in the prompt, a version, or a change to a recorded choice. Do not guess these, because a wrong guess costs a restructure later. When the prompt already answers every question, do not ask again.

## Bootstrapping

Ask in two batches. Flag the default for each. Confirm before writing anything.

**Batch 1, the product.**

1. What is it, in one sentence?
2. One repo or several? A part earns its own repo only for an independent release cadence that is real today, external consumers, or a visibility boundary.
3. A deployed application, or a published package?
4. Which sibling repos does this one expect, such as docs or an SDK it consumes?
5. Where do docs live: in this repo, a docs repo, or nowhere?
6. Open source or private?

**Batch 2, the pieces.**

1. Backends: how many, which language each, and what they coordinate through?
2. Does any surface need its own identity plane, such as operator versus user? A different look is not a yes.
3. Frontends: how many, which kind each? Theme both modes or light only? Any non-web surface: desktop, mobile, PWA?
4. Which data engines does the requirement need?
5. Which external pieces already exist, such as a hosted Postgres or a host proxy?
6. When Python is present: ML or app?
7. Does anything touch an LLM?
8. Which protection tier for each public app?

Ask each of these rather than infer it, because each answer changes the tree and a wrong guess costs a restructure later.

**Confirm.** Restate what you heard as 5 to 10 bullets and get a yes. Then:

1. Copy `template/` whole. Copy nothing from `additional-template/`. A bootstrap ships the four-rung ladder and nothing more: no hooks, no `memory/`, no browser suite. The user adds each later by name.
2. Delete the app folders the product does not need. A folder exists only when used.
3. Rename every `example-*` folder to its role name. `11_conventions.md` § Naming gives the form.
4. Resolve every `<version>` with the user. `ctl check` lists each file that still holds one. Never fill one from memory.
4a. Keep the lint config each app ships (`[tool.ruff]`, `.oxlintrc.json`, `clippy.toml`, `.golangci.yml`); `ctl check` fails an app without one. Change a threshold only with the user, and record it in `AGENTS.md`.
5. Fill every section of `template/AGENTS.md`. The file is the example: nine sections, each with its table or its one-line placeholder. Replace every `<angle-bracket>` choice with the real one.
6. Run `ctl setup`, then `ctl gate`. Report each exit code as it is. A red rung is a finding to fix, not a note.
7. End with `ctl --help` and the manual path in the README. Name the optional rungs and the add-ons in one line, so the user knows they exist, and stop there.

## Auditing

1. Read `AGENTS.md`. A recorded choice or a recorded deferral is not a finding. An optional rung or add-on the repo never installed is not a finding either; an installed one that drifted is.
2. Run `./ctl check` from the repo root, on its own line and not through a pipe, because a pipe returns the last command's exit code and not the check's. Put its exit code and every red line in the report. It proves the mechanical rules and nothing else does. A report that says what the check "would" find is not an audit.
3. Walk the layers in the order `11_conventions.md` § Audit order gives, lowest first. Report every layer. Order the table by layer, so the reader fixes the lowest first. Do not stop at the first failing layer, because a finding hidden behind a lower one sends the reader back for a second audit.
4. Never read a filled `.env.*` file, because it holds live secrets. Read the `.env.*.template` files.
5. Report a table: file, rule broken, fix. The first row is the `ctl check` result.

## A single question mid-task

Find the page from the table above. Answer from it, and point at the template path that shows the answer. If the answer changes a recorded choice, say so and record it. If no page covers it, resolve from the principles and write the decision into `AGENTS.md`. Never improvise a pattern inline, because an inline pattern has no home and the next agent cannot find it.

## Out of scope

Training loops, remote GPUs and model serving: decide per project and record in `AGENTS.md`. Docs-site content: the `agent-ks` skill. Instruction wording in `AGENTS.md` or `CLAUDE.md`: the `instruction-writing` skill. Host proxies and TLS, Kubernetes and cloud deploy targets: outside the repo, mentioned only where the edge meets them.
