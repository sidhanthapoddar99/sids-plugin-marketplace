# project-setup

One skill: how a repo is shaped. It answers a bootstrap ("set up this project"), an audit ("does this repo follow the rules"), and a single question mid-task ("where does this go"). The same rules serve all three, so the answer does not depend on which one you asked.

The skill is opinionated on purpose. One repo tree, one entrypoint (`ctl`), one origin, one file per kind of value. A convention that is written once and checked by a script beats a fresh decision on every task, because an agent reads the file cold and the check does not.

## Contents

| Path | What it is |
|---|---|
| `skills/project-setup/SKILL.md` | The workflow for each mode, the page table, and the pointers into the template |
| `skills/project-setup/references/01_layout.md` to `11_conventions.md` | Eleven pages. Each owns one question: layout, env, routing, stack, frontend, backend, security, `ctl`, production, testing, conventions and audit order |
| `skills/project-setup/template/` | A complete instance of the tree. `ctl`, `scripts/`, `docker/`, the env templates, `AGENTS.md` and the conformance test are real and run. The app folders are shape only |
| `../../evals/project-setup/` | The test prompts and fixtures used to check the skill with skill-creator. Kept outside the plugin so installs do not carry them |

## What the template gives you

- `ctl`: one entrypoint. `ctl setup`, `ctl check`, `ctl dev`, `ctl up +modifier`, `ctl migrate`, `ctl test`, `ctl gate`. Run `template/ctl --help` for the list.
- `ctl check`: the conformance floor. It runs every rule, prints every failure, and exits 0 only when all of them passed. It is also a rung of `ctl gate`.
- Three root env files with committed templates: `.env.secrets`, `.env.data`, `.env.proxy`. A backend reads them through `config.yaml` with `${VAR}`. A frontend has no env file.
- `docker/compose.base.yaml` with no ports, plus modifiers that add exposure. Base is production.
- `AGENTS.md`: the brief. Every chosen variant, exception and deferral is recorded there, and an audit compares the repo against it.

## What stays out

Docs-site content is the `agent-ks` plugin. Training loops, remote GPUs and model serving are decided per project and recorded in `AGENTS.md`. Host proxies and TLS live outside the repo.

## Install

```
/plugin install project-setup@sids-plugin-marketplace
codex plugin add project-setup@sids-plugin-marketplace
```

## License

[PolyForm Noncommercial License 1.0.0](LICENSE). Any noncommercial use is permitted: personal projects, study, hobby work, education, public research, charitable and public-interest organisations. Commercial use is not permitted. For commercial-use licensing, contact `developer@neuralabs.org`.
