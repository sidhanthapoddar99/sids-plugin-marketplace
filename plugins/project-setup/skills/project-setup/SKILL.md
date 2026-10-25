---
name: project-setup
description: >-
  Use this skill to bootstrap, audit or restructure a repo, to grow it into a production line, or to answer where code and configuration belong mid-task. It owns apps/, apps/packages/, data/, logs/, one ignored root .env and committed .env.template grouped by kind, backend config.yaml, single-origin routing, Docker Compose configs and modifiers, services and presets, and ctl (dev, up, db migrate, manage, gate, merge, worktree), copied from the template, never rewritten. Covers stack choices, frontend and backend folder shapes, tokens.css and typography rules, schema ownership, security, development sign-in (AUTH_ENABLED), production, the four-rung gate floor, gate modes, gate receipts and TESTING settings, versions and releases set at merge, Rust and WASM release builds (profile, wasm-opt, image caches, binary size), worktrees in .worktrees/, optional add-ons and the AGENTS.md and CLAUDE.md contract. Use when adding a frontend, a backend or a ctl verb, changing ctl, scripts/ or these boundaries, when tests or merges feel slow, or when shipping, versioning or slimming a build. Skip implementation inside one file, migration SQL, docs content (agent-ks), instruction wording (instruction-writing), Kubernetes and cloud deploy targets.
---

# project-setup

One repo shape, one entrypoint, one origin. This skill decides where things go and how they connect, from the first commit to a production line that ships releases. It answers three kinds of request with the same rules: a bootstrap, an audit, and a single question mid-task. The rules live in the twenty pages under `references/`. This file is the workflow and the map.

## Stages

A repo meets the pages in this order. Each stage adds to the one before and replaces nothing.

| Stage | What joins | Pages |
|---|---|---|
| Prototype | the template copy, the four-rung gate, `ctl dev` | `01`–`08`, `10b`, `11` |
| Parallel work | worktrees on warm slots, gate receipts, `ctl merge` | `13`, `10d`, `15` |
| First deploy | the production checklist, the security review, the `audit` and `build` rungs | `09`, `07`, `10a`, `12` |
| Production line | versions set at merge, a version log, release builds that are small and fast | `15`, `16` |

The process lives in `ctl`, not in the brief. When a habit keeps coming back, such as a gate run three times or a version raised in every commit, the fix is a `ctl` step or a `ctl check` rule, because a rule an agent must remember drifts and a rule `ctl` runs does not.

## Before anything

1. Read `AGENTS.md` at the repo root when it exists. It records the choices this repo has already made, and a recorded choice is never a finding.
2. In an existing target repo, inspect the root and the directory hierarchy of paths in scope for `CLAUDE.md`. Handle any found file under `references/11_conventions.md` § The agent brief.
3. Find the page that owns the question in the table below. Read that page, not the set, because each page owns one question and the set is about 2,500 lines.
4. Find the skill folder, the folder that holds this `SKILL.md`, because every runnable file comes from its `template/`, and its `scripts/template.sh` copies and checks them. Below, `<skill folder>` stands for its path. Claude Code prints the folder on the first line of the loaded skill, as `Base directory for this skill: <path>`. Codex lists each skill with the path of its `SKILL.md`. When that path starts with an alias such as `r3/`, replace the alias with the folder the skills catalogue maps it to. On another host, take the folder of the `SKILL.md` file you opened. `test -f <skill folder>/template/ctl` confirms the folder. If you cannot find it, stop and ask the user for the path.
5. In an existing repo, run `bash <skill folder>/scripts/template.sh verify .` once before you add an app or a verb, or change `ctl` or `scripts/`. A hand-made `ctl` looks like the template's from outside, and each change to it spreads the drift this skill prevents. The first line of the output is the verdict.
   - `green`: `ctl` and its shared helpers, the files in `scripts/common/`, are the template's. Extend them as `references/08_ctl.md` § Extending the copied router says.
   - `red — not from the template`: tell the user so in one line. Offer to adopt the template (`references/08_ctl.md` § Adopt an existing repo), and adopt it only when the user says yes. Until then, do the parts of the task that need no change to `ctl`. Ask before you add a verb to the hand-made `ctl`, because each verb added there is one more to port later.
   - Any other `red`: the repo is a template copy, but its shared helpers differ from this skill's. Report the line, and offer the step that `references/08_ctl.md` § Verify gives for that verdict. Take the step only when the user says yes, because it replaces helpers that every verb runs. Meanwhile, extend the router as § Extending the copied router says.
6. Get `ctl` and `scripts/` only as a copy of `template/`. Change the copy only by deletion, at an `[ADAPT]` point (a knob the template marks with a `# [ADAPT]` comment), or with a new worker for a new verb. Never write `ctl` or a shared helper yourself, because the helpers carry env loading, process ownership, locks and failure handling, and a smaller rewrite still passes every app test. `ctl check` compares `scripts/common/` with the template, so a rewrite turns the gate red.
7. Treat `additional-template/` as opt-in. It holds the add-ons: git hooks, `memory/`, a browser suite. Its `README.md` says when each is usually earned. Install one only when the user asks. Recommend one with its reason, then wait. The same holds for a ladder rung beyond the four-rung floor.

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
| How development runs without sign-in: `AUTH_ENABLED` and the reserved `default` user | `references/14_development-sign-in.md` |
| What do I type | `references/08_ctl.md` |
| How `ctl up` assembles a stack: configs, modifiers, services, presets, include | `references/08a_ctl_docker.md` |
| Where worktrees live; warm slots, `ctl worktree`, a slot's `.env`, the trim, disk wear | `references/13_worktree.md` |
| What makes it prod | `references/09_production.md` |
| How HTTP exposure and TLS are configured | `references/12_http-and-tls.md` |
| What a person reviews by hand | `references/10a_review.md` |
| What is green; the ladder; the static rungs | `references/10b_static-checks.md` |
| Where tests live; the dynamic rungs | `references/10c_dynamic-tests.md` |
| How fast a test run is, and what it may use: TESTING settings, gate modes, gate receipts, the one-run lock, Rust debug info | `references/10d_test-speed-and-resources.md` |
| How versions move and work lands: numbering, `ctl merge`, the version step, packages, the version log | `references/15_releases.md` |
| How a Rust server or WASM module ships small and fast: the release profile, `wasm-opt`, image stages and caches, disk wear | `references/16_rust-production.md` |
| What holds everywhere; the audit order | `references/11_conventions.md` |
| Example of a collaborative editor with shared browser/server WASM and intent synchronization | `references/examples/shared-wasm-document-engine.md` (optional example, not a prescribed stack) |

`template/` is the floor of the tree. `ctl`, `scripts/`, `docker/`, the env template and `AGENTS.md` are real and run. `additional-template/` holds the add-ons at the same relative paths; they are real too, and a repo gets them one at a time on the user's word. The app folders under `apps/` are shape only: each file's comment states what it holds, and the code is written per project. A page may name a file the template does not carry, such as `gunicorn.conf.py` or `lib/theme.ts`. Those are written per project too. `template/ctl --help` is the verb list.

For changes to ctl’s environment loader, run the [ctl tooling tests](tests/ctl/README.md).

## Principles

The fallback for a question no page covers. Each line points at the page that owns the rule, so the rule has one home and this list stays short.

1. **One tree for every repo** (`01_layout.md`). A repo with one app and one with five look the same from the root, so nothing is re-decided when the second app arrives.
2. **One entrypoint, `ctl`** (`08_ctl.md`). A worker is a script under `scripts/` that one verb runs; a rung is one step of `ctl gate`. A rung calls the same worker the dev verb calls, so the check and the loop cannot drift.
3. **Same-origin routing** (`03_routing.md`). Production uses one origin. Each frontend's development server proxies backend prefixes, so browser API calls stay relative without CORS. Cross-frontend development flows needing a shared origin require an explicit gateway.
4. **One environment contract, grouped by kind** (`02_env.md`). Root `.env` settings use the grouped `.env.template` contract; backend defaults live in `config.yaml`. See the page for loading and exposure boundaries.
5. **Base is prod** (`08a_ctl_docker.md`, `09_production.md`). A config (`compose.<name>.yaml`, `base` is the whole stack) has no ports and modifiers add exposure, because compose lists only union, so exposure can only be added, never removed.
6. **Promote when shared, never before** (`11_conventions.md`). A thing moves up a scope at its second consumer, because a premature package is a second manifest to keep green for nothing.
7. **Convergence is the design** (`05_frontend.md`). Tokens and a typography allowlist in `AGENTS.md` override `frontend-design` once they exist, because a bold new look on every page is drift, not design.
8. **Green means a `ctl gate` run passed over the whole change** (`10b_static-checks.md`, `10d_test-speed-and-resources.md`). A check exits 0 only when the rule was proved, so green never means "nothing ran". A run that cannot tell what a change reaches checks everything. A tree that already passed is green without a second run. The floor is four rungs that cost seconds; every further rung, hook and suite is the user's call, because a prototype pays for each on every commit.
9. **Tool versions are `<version>` until resolved with the user** (`04_stack.md`). A version from memory is a guess that installs, so `ctl check` names every placeholder and `ctl setup` refuses to install while one remains.
10. **The brief is the contract** (`11_conventions.md`). Every chosen variant and exception is recorded in `AGENTS.md`, because the skill is not always loaded and the brief is, and an audit compares against the brief. The brief holds current facts only, under the size `ctl check` enforces; plans and deferrals go in the tracker. `CLAUDE.md` beside it holds `@AGENTS.md`, so Claude Code and Codex read one text.
11. **One gate per merge, versions at merge** (`15_releases.md`). `ctl merge` lands a branch: it sets the versions the branch changed, gates the merged tree once and fast-forwards. A branch commit leaves versions alone, because people receive a merge, not a commit.

## When you run this skill

- Decide and keep going: which page answers, the wording of a finding, the order in which you delete and rename.
- Decide and record in `AGENTS.md`: a structural choice a page leaves open, any exception to the tree, and a shared helper you change on purpose. The helper gets a `template-core <path>` line under `## Exceptions to the standard layout`, as `08_ctl.md` § The template core in every repo shows. An unrecorded choice reads as drift at the next audit.
- Never on your own: an add-on from `additional-template/`, or a ladder rung beyond `lint typecheck test check`. A recommendation is welcome; the install waits for the user's yes.
- Stop and ask: a bootstrap question below whose answer is not in the prompt, a version, a change to a recorded choice, the skill folder when you cannot find it, or a tool that `ctl setup` cannot install. Do not guess these, because a wrong guess costs a restructure later. When the prompt already answers every question, do not ask again.

A missing tool is installed, never coded around (`11_conventions.md` § A missing tool is installed, never coded around, gives the reason). When a worker stops on a missing tool, its message names the install step: declare the tool in `.mise.toml`, resolve its version with the user, then run `ctl setup`. A tool that resolves to a mise shim and cannot run is missing in the same way. When mise cannot provide the tool, give the user the exact install command. Then stop.

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

**Confirm.** Restate what you heard as 5 to 10 bullets. Add the versions: one line for each toolchain, data engine and framework the answers keep, with the version to pin. Take each default from a live source, because a version from memory is a guess that installs: `mise ls-remote <tool> | tail -1` for a tool in `template/.mise.toml`, the image registry for an engine, the package registry for a package. `jq` is always on the list, because `ctl` itself uses it. Get one yes for all of it, so no later step waits on the user.

**When the user asks for no questions.** Use every answer the prompt gives. Ask nothing until the work is done. A missing batch answer still stops you before the copy, because it changes the tree. A missing version does not stop you, because it only fills a placeholder. Leave its `<version>` in place, and run every step below except step 8. Then end with one question in this shape:

```text
These versions are still <version>. The defaults come from the live sources named.
- jq: 1.8.1 (mise ls-remote jq)
- react: 19.2.0 (npm registry)
Reply yes to pin these, or name other versions. Then I write them and run ./ctl setup and ./ctl gate.
```

Then run these steps in order:

1. **Copy the template.** This is the first change you make, because every later step edits the copy. From the target repo root, run `bash <skill folder>/scripts/template.sh copy .`. It copies `template/` whole and prints one line. When a file it would write already exists, it copies nothing and names each such file. Rename those files and run it again. Merge their old text into the new files at step 6. When the repo already has `ctl` or `scripts/`, the confirmed bootstrap includes adopting them: follow `08_ctl.md` § Adopt an existing repo instead. Copy nothing from `additional-template/`. A bootstrap ships the four-rung ladder and nothing more: no hooks, no `memory/`, no browser suite. The user adds each later by name.
2. **Delete what the answers rule out, and nothing else.** Use the table below. Keep every other file, even a verb whose app is not written yet, because a verb deleted now comes back later as a hand-written one. Keep `scripts/common/` whole outside its `[ADAPT]` blocks, because `ctl check` compares it with the template. Then find what still names each dropped piece. Run `grep -rniE --exclude-dir=node_modules '(^|[^a-z])<name>([^a-z]|$)' ctl scripts docker apps .env.template .gitignore` twice, once with its folder name and once with its compose service name. Resolve every line it lists, whether or not the line is an `[ADAPT]` row. Delete a line or block that serves only the dropped piece. Take only the dropped name out of a list that also names a kept piece. Leave a line that uses the word for something else.
3. Rename every `example-*` folder to its role name. Update the rows that name it in the same way. `11_conventions.md` § Naming gives the form.
4. Write each confirmed version in place of its `<version>`. `./ctl check` lists each file that still holds one. Never fill one from memory.
5. Keep the lint config each app ships (`[tool.ruff]`, `.oxlintrc.json`, `clippy.toml`, `.golangci.yml`). `ctl check` fails an app without one. Change a threshold only with the user, and record it in `AGENTS.md`.
6. Fill every section of `template/AGENTS.md`. The file is the example: eleven sections, each with its table or its one-line placeholder. Replace every `<angle-bracket>` choice with the real one. Keep the copied `CLAUDE.md`, which holds `@AGENTS.md`. When the product has a version, list its manifests in `VERSION_FILES` in `scripts/release/versions.sh`.
7. Run `./ctl setup env`, then `./ctl check`. `ctl setup env` writes `.env`, generates the declared credentials and creates the storage folders. It installs nothing, so it runs while a `<version>` remains, and `ctl check` can then test the env contract and the compose files. Fix each red line except an unresolved version.
8. Run `./ctl setup`, then `./ctl gate`, before you commit the copy. `ctl setup` installs every tool in `.mise.toml`, `jq` among them. A plain `ctl gate` checks what the uncommitted changes reach, so while the copy is uncommitted it checks every rung on every app. Report each exit code as it is. A red rung is a finding to fix, not a note.
9. Run `bash <skill folder>/scripts/template.sh verify .`. Report its verdict. Give each difference it lists a reason: a row of the table below, an `[ADAPT]` point, a rename, or a new worker. A red verdict is a finding to fix, because it means a shared helper is not the template's.
10. End with `ctl --help` and the manual path in the README. Name the optional rungs and the add-ons in one line, so the user knows they exist, and stop there.

**What each answer deletes.** Paths are in the copied repo. A file this table does not name stays.

| Answer | Delete |
|---|---|
| Every app or engine the answers drop, beside its own row below | its service in `docker/compose.base.yaml`, when it has one, and every entry that names that service: a `depends_on` entry; the `web` edge's upstream, prefix and `NGINX_ENVSUBST_FILTER` entries, with the matching `location` block in the edge's `nginx/nginx.conf.template`; and its line in each `docker/compose.m.*.yaml`, such as an engine's port in `compose.m.expose_db.yaml`. Its row in `GATE_TARGETS` (`scripts/gate/_targets.sh`) and its name in `GATE_REACHES` (`scripts/gate/_changed.sh`), because the gate stops on a name that has no row. Its entries in `scripts/dev/_apps.sh`. Its keys in `MODIFIER_REQUIRES` (`scripts/common/_lib.sh`) and in `.env.template` |
| No Python backend | `apps/example-api-python/` and `scripts/admin/`; `python` and `uv` in `.mise.toml` |
| No operator plane (Batch 2, question 2) | `scripts/admin/`, the backend's `manager.py`, and the `manage` lines in `ctl` (`08_ctl.md` § `ctl manage`) |
| No Rust backend | `apps/example-engine-rust/`, `scripts/dev/rust-watch.ts`, `scripts/dev/rust-watch.config.ts`, `scripts/dev/clean.sh` and the `clean rust` lines in `ctl`; the `engine` entries in `scripts/dev/_controllers.sh` and `rust_app_names` in `scripts/dev/_apps.sh`; `rust` and `watchexec` in `.mise.toml` |
| No Go CLI | `apps/example-tui-go/`; `go` and `golangci-lint` in `.mise.toml` |
| One Vite frontend | `apps/example-multi-web-app/` and `apps/example-dashboard-nextjs/`. The `web` service stays, because the Vite app takes it over: point its `dockerfile:` at `example-single-web-app-vite/Dockerfile` and delete its `WEB_APP_PREFIX` and `WEB_DOCS_PREFIX` lines, as that Dockerfile's header says |
| A group of static frontends | `apps/example-single-web-app-vite/`, and each child of `apps/example-multi-web-app/` the answers do not name (`app/`, `landing/`, `docs/`) |
| No server frontend | `apps/example-dashboard-nextjs/` |
| No TypeScript frontend and no Rust backend | `bun` in `.mise.toml` |
| A package under `apps/packages/` that no kept app links | that package |
| A data engine the answers drop | its schema job (`migrate` for Postgres, `neo4j-init` for Neo4j), which the first row treats as a dropped service too; its name in the `dev` line of `docker/presets.yaml`; `apps/database/<engine>/`; its name in `DATA_SVCS` and `SCHEMA_SVCS` in `scripts/common/_lib.sh` (both are `[ADAPT]` blocks) |
| No data engine at all | what `08_ctl.md` § Without a data core lists, `scripts/db/` among it |
| Private, and no license named | `LICENSE` |

`jq` stays in `.mise.toml` for every answer, because `ctl` itself uses it.

## Auditing

1. Read `AGENTS.md`. A recorded choice, or a deferral recorded in the tracker, is not a finding. An optional rung or add-on the repo never installed is not a finding either; an installed one that drifted is.
2. Run `./ctl check` from the repo root, on its own line and not through a pipe, because a pipe returns the last command's exit code and not the check's. Put its exit code and every red line in the report. It proves the mechanical rules and nothing else does. A report that says what the check "would" find is not an audit. Then run `bash <skill folder>/scripts/template.sh verify .`, because `ctl check` compares the helpers with the repo's own manifest and only `verify` compares them with this skill's.
3. Walk the layers in the order `11_conventions.md` § Audit order gives, lowest first. Report every layer. Order the table by layer, so the reader fixes the lowest first. Do not stop at the first failing layer, because a finding hidden behind a lower one sends the reader back for a second audit.
4. Read `.env.template` when auditing. Do not read a filled `.env` or other local env file, because it may hold live secrets.
5. Report a table: file, rule broken, fix. The first row is the `ctl check` result, with the `verify` verdict beside it.

## A single question mid-task

Find the page from the table above. Answer from it, and point at the template path that shows the answer. If the answer changes a recorded choice, say so and record it. If no page covers it, resolve from the principles and write the decision into `AGENTS.md`. Never improvise a pattern inline, because an inline pattern has no home and the next agent cannot find it.

## Out of scope

Training loops, remote GPUs and model serving: decide per project and record in `AGENTS.md`. Docs-site content: the `agent-ks` skill. Instruction wording in `AGENTS.md` or `CLAUDE.md`: the `instruction-writing` skill. Host proxies and TLS, Kubernetes and cloud deploy targets: outside the repo, mentioned only where the edge meets them.
