---
name: instruction-writing
description: Write, edit, audit or review an instruction file for an AI agent. Covers CLAUDE.md at user, project and local level, AGENTS.md for Codex, .claude/rules/ files, SKILL.md bodies, reference files under a skill, system prompts for an agent, and briefs for subagents. Ten rules, each with its reason, plus a rubric a fresh agent can run as an independent review. Use it whenever the user creates or touches any of those files, asks why an agent ignored a rule, asks what belongs in CLAUDE.md versus a skill, or asks to trim, tighten or rewrite agent instructions, even mid-task. Reply language and tone stay in the user CLAUDE.md. The skill test loop stays with skill-creator.
---

# instruction-writing

## What the file is for

An agent reads an instruction file cold. It has none of your context, it reads the file many turns after you wrote it, and it meets a case you did not picture. Every rule below follows from that fact. The word "agent" below means the reader of the file you are writing. The table under rule 10 names the kinds of file and sets the budget and the content each must carry.

## How to use it

1. Name the kind of file from the table under rule 10, because the kind sets the budget.
2. Read the file and every file it imports or points at, because a rule can only be checked against its neighbours.
3. Write or rewrite the file under the ten rules.
4. Run `references/review-rubric.md` on the result, yourself or through a second agent, so the file has failed its own review once before the owner sees it. The owner is the person who maintains the file, usually the user.
5. Hand back the file and the findings, so the owner sees what the review would still fail.

## When you run this skill

- Decide and keep going: wording, sentence splits, the order of sections, which example to show.
- Decide and record in your reply: a fact you moved to another file, a line you deleted because the agent already does it, or a rule whose reason you do not know. For that last one, write "Reason not recorded. Ask the owner." in the reason's place, because an invented reason reads as true and teaches the next agent a false rule.
- Stop and ask: a fact the file needs that you do not have, such as a command, a path or a threshold. Do not invent one, for the same reason. End the turn with the question.

## The rules

**1. Put the reason beside the rule.** Say what to do and why in the same sentence, or the next one. One reason may serve a run of rules in one paragraph when it plainly covers them all. A bare rule gets pattern-matched, and the first time a case looks slightly different the agent skips it. A reason covers the cases the author never listed. Keep the reason to a clause, because it loads as often as the rule and a long one buries it. Pair 1 in `references/examples.md` shows the form.

**2. One home per fact.** Each rule lives in one file. Every other file points at it. A fact with two homes drifts, and the copy is the one that goes stale. Two files that disagree make the agent pick one at random. When two hosts need the same rules, keep one file. Import it from the other host's file. A CLAUDE.md whose first line is `@AGENTS.md` gives Claude Code and Codex the same text.

**3. Point, do not paste.** A file loaded every turn holds facts, hard limits (see rule 7) and pointers. A fact is a line every task needs, such as the test command. Detail is what only some tasks need, such as the commit form. Detail goes in files the agent opens on demand, because cost is paid per turn, not per file. A pointer is a path in backticks that the agent opens when it needs it. An `@import` is not a pointer, because it loads at launch with the file that holds it. Apply the deletion test: delete any line the agent would follow without it, because a long file buries the rules that matter and a current model needs little telling. Pair 2 in `references/examples.md` shows the form.

**4. Write plain imperative sentences.** Put one instruction in each sentence, so the agent can act on it without splitting it first. Write in the active voice, so the agent knows who acts. Give each word one meaning. Give each thing one name. Then nothing has to be reconciled. Define a term the first time you use it, because a reader with no context cannot ask what you meant. This is ASD-STE100, simplified technical English. Shorten by splitting sentences. Do not shorten by dropping the words that hold a sentence together, because a fragment or an arrow chain is shorter and harder to act on.

**5. Show, do not describe.** When the shape of a thing is the point, give one filled example in a code block, with the guidance written inside it under each part. A description of a shape makes each reader rebuild it, and each reader rebuilds it differently. Pair 5 in `references/examples.md` shows a brief in this form.

**6. No history.** The file describes the current system only. Replace corrected text. Do not keep it with a note, because "this used to say" costs tokens every turn and gives the agent two versions to weigh. Git holds the history. So does the project's issue tracker, when it has one. Pair 3 in `references/examples.md` shows the form.

**7. Reasons over emphasis.** ALL-CAPS MUST and NEVER are a yellow flag. Current models respond strongly to the prompt, so emphasis causes over-triggering. A hard limit is a rule whose only exceptions are written into it. Put every hard limit once, under one heading such as `## Hard limits`, so the agent can tell which lines have no exception. A hard limit you would grant an exception to is guidance, so keep hard limits few. In Claude Code, also enforce a hard limit with a hook or a `permissions.deny` entry in the settings file at the same level as the instruction file, `~/.claude/settings.json` for a user file and `.claude/settings.json` for a project file, because prose is advisory. Codex has no hook, so there the prose is the only copy. Everything else is guidance with its reason, so the agent can weigh it. Pair 4 in `references/examples.md` shows the form.

**8. Say what the agent decides alone.** Name three tiers. The first is what it decides and keeps going. The second is what it decides and records. The third is what stops it to ask. Without the tiers an agent asks at every fork or never asks. Keep the third tier narrow, because every stop parks the run until a human answers. Name what clears it for that file's agent. For an agent that changes a system, that is an irreversible outward action, a product question no engineering principle settles, or a break with the stated architecture. For a narrower job, it is the one thing the agent cannot supply itself. A reference file needs no tiers, because it gives detail and takes no decisions. Pair 5 in `references/examples.md` shows the section filled in.

**9. The cold-read test.** A reader with none of your context can act on the file. If they would ask "but what exactly", it is not written. Prefer a line the reader can verify. "Run `npm test` before committing" passes. "Test your changes" does not.

**10. Match the file to its agent.** A file over its budget buries the lines that matter. A file short of the content its kind must carry leaves its agent guessing.

| File | Loaded | Budget and content |
|---|---|---|
| CLAUDE.md, rules file without `paths`, system prompt | at launch, every session | under 200 lines. Facts, hard limits, pointers |
| AGENTS.md | at launch. Codex stops reading once all AGENTS.md files pass 32 KiB together | under 200 lines. Same content as CLAUDE.md |
| rules file with `paths` | when the agent touches a matching file | under 200 lines. Facts and pointers for that path only |
| SKILL.md description | always, in the skill list | under 1,536 characters. What the skill does, then every case that should trigger it, a little pushy, because models under-trigger and this is the only text they see before choosing |
| SKILL.md body | when a task matches. It stays for the session | under 500 lines. The workflow, not the background |
| reference under a skill | when the body points at it | no fixed limit. Where the detail lives |
| brief for a subagent | at spawn, once. The agent never sees your conversation | no fixed limit. Self-contained: goal, files, hard limits, tiers, return shape |

## References

- `references/review-rubric.md`: the ten rules as pass-or-fail checks, with the failing sentence quoted. Step 4 above runs it.
- `references/examples.md`: five before-and-after pairs, one per rule that has a form to copy. Open it when the rule is clear but the fix is not.

## Sources

- https://code.claude.com/docs/en/memory
- https://code.claude.com/docs/en/best-practices
- https://code.claude.com/docs/en/skills
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1
- https://learn.chatgpt.com/docs/agent-configuration/agents-md
- https://agents.md/
- skill-creator plugin, `SKILL.md`, sections "Writing Style" and "Explain the why"
