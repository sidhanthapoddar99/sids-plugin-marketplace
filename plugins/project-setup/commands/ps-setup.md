---
description: Bootstrap, audit, or propose a layout — using Sid's conventions for repo structure, frontend / backend architecture, databases, docker / compose, deployment, env / config, design tokens, modularity, ML orchestration. For one-off architectural questions ("where should X go", "should I split Y"), the `project-setup` skill triggers automatically — no slash command needed. Use `/ps-setup` only for the wholesale bootstrap / audit / suggest flow.
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

1. **Open the skill** at `skills/project-setup/SKILL.md` and follow its workflow.
2. **Run the question flow** from `skills/project-setup/references/01_question-flow.md` in order. Ask only what you don't already know from the conversation.
3. **Pick a topology** from `skills/project-setup/references/topologies/*` based on the answers. If the user's shape doesn't cleanly match one, name the closest two and ask.
4. **Show the proposed tree** as text. List every file you will create.
5. **Ask once** before writing anything.
6. **Apply** — write the files, dropping snippets from `assets/snippets/` where they fit. Use `${VAR}` placeholders consistently.
7. **Post-init** — point the user at:
   - `mise install` to install the runtime contract
   - `cp .env.example .env` to start the secrets contract
   - `/docs-init` (from the `documentation-guide` plugin) to scaffold `docs/`
   - `ctl dev` to run the host dev loop once secrets are filled

## Audit mode

The user wants to know how their current repo compares to the conventions. **Read-only — never edit files.**

1. Read the current repo's top-level structure (`apps/`, `packages/`, `docker/`, `infra/`, `data/`, `scripts/`, `docs/`, `.claude/`, `.mise.toml`, `.env.example`, `README.md`, `CLAUDE.md`). Do **not** read `.env` files (secrets).
2. Identify the closest topology by file evidence + by asking 1–2 disambiguating questions (e.g. "are there sibling repos I should know about?").
3. For each convention area, compare the repo to the reference. List in three categories:
   - **Matches** — already aligned
   - **Drift** — minor deviation (e.g. flat `backend/` instead of `apps/backend/`)
   - **Missing** — convention not present (e.g. no `ctl` dispatcher, no `docker/` folder, no `tokens.css`)
4. Stop. Do not propose changes; just the report.
5. Tell the user `/ps-setup suggest` produces a remediation plan if they want one.

## Suggest mode

The user wants a concrete proposal for restructuring their current repo. **Do not edit yet.**

1. Run audit first (internally). Identify topology + drifts + gaps.
2. Produce a remediation plan:
   - **Rename** — `backend/` → `apps/backend/`, `frontend/` → `apps/frontend/`, etc.
   - **Move** — compose files into `docker/`, init scripts into `infra/<service>/`, bind-mount dirs under `data/`.
   - **Add** — missing pieces: `ctl` dispatcher, `tokens.css`, `.mise.toml`, `.env.example`, `CLAUDE.md`.
   - **Split** — files exceeding the 500-line cap.
3. Show the proposed end-state tree.
4. Ask the user which pieces they want to apply. They can opt into subset.
5. Apply only the opted-in pieces, one at a time, with confirmation between batches.

## Style

- Be concise. Long question flows lose users; ask in batches of 3–4 with reasonable defaults flagged.
- Cite the reference files inline so the user can read why a convention exists (`see references/env-and-config/frontend-env-isolation.md`).
- When dropping a snippet, name the source (`from assets/snippets/dev-wrapper.sh`).
- Never invent file paths — consult `references/examples-index.md`.
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
