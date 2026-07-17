---
description: Bootstrap, audit, or propose a layout — using the plugin's opinionated conventions for repo structure, frontend / backend architecture, databases, docker / compose, deployment, env / config, design tokens, modularity, ML orchestration. For one-off architectural questions ("where should X go", "should I split Y"), the `project-setup` skill triggers automatically — no slash command needed. Use `/ps-setup` only for the wholesale bootstrap / audit / suggest flow.
argument-hint: "[init | audit | suggest]"
---

# /ps-setup — project setup, audit, or suggest

You are the user-facing entrypoint of the `project-setup` plugin. Delegate the actual work to the `project-setup` skill — its references library knows the conventions; you orchestrate the flow.

## Argument parsing

```
$ARGUMENTS
```

- empty (or `init`) → **init mode**
- `audit` → **audit mode**
- `suggest` → **suggest mode**

If the argument is anything else, tell the user the three valid modes and stop.

## Init mode

The user wants to bootstrap a new project.

1. **Open the skill** at `skills/project-setup/SKILL.md` and follow its Workflow A — it walks the four levels top-down (`references/levels/00_altitude-model.md`): L1 ecosystem → L2 repo → L3 per-app, installing L4 as CLAUDE.md doctrine.
2. **Run the question flow** from `skills/project-setup/references/01_question-flow.md` in order (it is level-ordered). Ask only what you don't already know from the conversation.
3. **Pick a layout** from `skills/project-setup/references/repo-setup/layouts/*` based on the answers. If the user's shape doesn't cleanly match one, name the closest two and ask. Confirm the variant picks explicitly (grouping topology, workspace rooting, core-vs-BFF, identity planes, migration style/owner).
4. **Show the proposed tree** as text. List every file you will create.
5. **Ask once** before writing anything.
6. **Apply** — write the files, dropping snippets from `assets/snippets/` where they fit. Use `${VAR}` placeholders consistently. **For the runtime layer, COPY the snippet files verbatim** — `cp -r "${CLAUDE_PLUGIN_ROOT}/assets/snippets/scripts" ./scripts && mv ./scripts/ctl ./ctl && chmod +x ./ctl`, plus `assets/snippets/docker/*` — then adapt by deletion (conformance floor: `references/repo-setup/runtime/script-overview.md`). Never regenerate them from the reference prose (the prose is abbreviated; the files are the source of truth). Generate `.gitignore` from `assets/snippets/env/gitignore.template`, keeping only the ecosystems present. Note `assets/` is a sibling of `skills/` at the plugin root, NOT under `skills/project-setup/`.
7. **Write the project CLAUDE.md** from `assets/snippets/claude/CLAUDE.md.template` with **every block resolved**: hard rules, the structure-contract block (recorded variant choices + skeletons + tripwire numbers + escalation pointer), and the styling-discipline block whenever there's a frontend. No unresolved `<placeholders>` may ship.
8. **Post-init** — point the user at:
   - `mise install` to install the runtime contract
   - `cp .env.example .env` (or `ctl setup`) to start the secrets contract
   - the docs plugin's init command to scaffold `docs/` (see `references/integrations/docs-integration.md`)
   - `ctl dev` to run the host dev loop once secrets are filled

## Audit mode

The user wants to know how their current repo compares to the conventions. **Read-only — never edit files.**

1. Read the current repo's top-level structure (`apps/`, `packages/`, `docker/`, `infra/`, `data/`, `scripts/`, `docs/`, `.claude/`, `.mise.toml`, `.env.example`, `.gitignore`, `README.md`, `CLAUDE.md`). Do **not** read `.env` files (secrets).
2. Read the project CLAUDE.md's **structure-contract block** — the recorded variant choices are the audit baseline (an unusual shape with a recorded choice is conformant; the same shape unrecorded is drift). **A missing structure contract is itself a red finding.**
3. Identify the closest layout by file evidence + by asking 1–2 disambiguating questions (e.g. "are there sibling repos I should know about?").
4. Walk the levels per the skill's audit instructions (`SKILL.md` § Audit / suggest mode; each `references/levels/` charter ends with its audit list): L1 sibling/docs contracts → L2 root contract + `ctl` conformance floor + compose + env split → L3 tripwire **counts** (features-per-app, files-per-feature) + skeleton presence + migration ownership → L4 mechanical greps (fetch-outside-`api/`, styling discipline).
5. For each convention area, list findings tagged by level:
   - **Matches** — already aligned
   - **Drift** — minor deviation (e.g. flat `backend/` instead of `apps/backend/`)
   - **Missing** — convention not present (e.g. no `ctl` dispatcher, a single-file `ctl` below the conformance floor, no `docker/` folder, no `tokens.css`, missing CLAUDE.md blocks)
6. Stop. Do not propose changes; just the report.
7. Tell the user `/ps-setup suggest` produces a remediation plan if they want one.

## Suggest mode

The user wants a concrete proposal for restructuring their current repo. **Do not edit yet.**

1. Run audit first (internally). Identify layout + drifts + gaps.
2. Produce a remediation plan:
   - **Rename** — `backend/` → `apps/backend/`, `frontend/` → `apps/frontend/`, etc.
   - **Move** — compose files into `docker/`, init scripts into `infra/<service>/`, bind-mount dirs under `data/`, a polyglot repo's JS workspace to its group folder.
   - **Add** — missing pieces: `ctl` dispatcher (+ `scripts/` up to the conformance floor), `tokens.css`, `.mise.toml`, `.env.example`, `.gitignore`, `CLAUDE.md` with all blocks resolved.
   - **Restructure** — tripwire crossings: a domain layer past ~8–10 feature folders, feature subdivision past ~10 files, the missing `pages/`/`api/` layers in a grown frontend.
   - **Split** — files exceeding the 500-line cap.
3. Show the proposed end-state tree. Batch the moves into a consolidation window (one PR/milestone where churn is already happening), not a trickle of renames.
4. Ask the user which pieces they want to apply. They can opt into subset.
5. Apply only the opted-in pieces, one at a time, with confirmation between batches.

## Style

- Be concise. Long question flows lose users; ask in batches of 3–4 with reasonable defaults flagged.
- Cite the reference files inline so the user can read why a convention exists (`see references/repo-setup/env-and-config/frontend-env-isolation.md`).
- When dropping a snippet, name the source (e.g. `from assets/snippets/scripts/ctl`). Copy the `scripts/` + `docker/` snippets verbatim; don't hand-rewrite them.
- Never invent file paths — consult `references/integrations/examples-index.md`.
- Never read `.env` files. `.env.example` is the contract.

## When info is missing

The skill is explicit about this: **ask, do not presume.** Common gaps:

- Sibling repos the user expects to coexist
- Whether this is an app vs ML project
- Frontend exposure of backend URLs
- Deployment target (single, multi, Traefik present, cloud)
- Theming requirements (both modes default; opt out for marketing)
- Build-time vs runtime for each env var

If you find yourself guessing, stop and ask.

## See also

- `skills/project-setup/SKILL.md` — the full skill instructions
- `skills/project-setup/references/` — the full conventions library
- `assets/snippets/` — fragments to drop in
