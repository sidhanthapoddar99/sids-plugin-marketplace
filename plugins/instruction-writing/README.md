# instruction-writing

One skill: how to write instruction files for AI agents. That means a CLAUDE.md at user, project or local level, an AGENTS.md for Codex, a `.claude/rules/` file, a SKILL.md body, a reference file under a skill, a system prompt for an agent, or a brief for a subagent.

The skill carries ten rules, each with its reason. The one that matters most: a rule must say why. A bare rule gets pattern-matched and skipped the first time the situation looks slightly different. The reason lets the agent take a better call in a case the author never listed.

## Contents

| Path | What it is |
|---|---|
| `skills/instruction-writing/SKILL.md` | The ten rules with their reasons, and the table of file kinds |
| `skills/instruction-writing/references/review-rubric.md` | A pass-or-fail checklist a fresh agent can run as an independent review |
| `skills/instruction-writing/references/examples.md` | Before-and-after pairs for the rules whose fix is not obvious |
| `../../evals/instruction-writing/evals.json` | The test prompts used to check the skill with skill-creator. Kept outside the plugin so installs do not carry them |

## What stays out

Reply language and tone rules live in the user CLAUDE.md, because they are always on. The skill test loop lives in skill-creator.

## Install

```
/plugin install instruction-writing@sids-plugin-marketplace
codex plugin add instruction-writing@sids-plugin-marketplace
```
