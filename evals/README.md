# evals

Test suites for the in-house skills, one folder per plugin. They serve the maintainer, not the installer: no host reads them, so they live here and not inside `plugins/`, where Claude Code and Codex would copy them to every install.

| Folder | Skill under test |
|---|---|
| `project-setup/` | `plugins/project-setup/skills/project-setup` |
| `instruction-writing/` | `plugins/instruction-writing/skills/instruction-writing` |

Each folder holds `evals.json` in skill-creator's schema and a `files/` folder with the fixtures the prompts point at. Paths in `files` are relative to the repo root, not to the skill, because the suite does not sit inside the skill.

To run one, follow the skill-creator loop with `--skill-path plugins/<name>/skills/<name>` and this folder's `evals.json`. Raw runs go under `plugins/<name>/evals-workspace/`, which is gitignored.
