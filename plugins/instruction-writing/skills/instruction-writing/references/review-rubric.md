# Review rubric for an instruction file

Use this to review any instruction file for an AI agent: a CLAUDE.md, an AGENTS.md, a rules file, a SKILL.md body, a reference file, a system prompt, or a brief for a subagent. You need no context beyond the file itself, the files it points at, and `../SKILL.md`. The rules and the budgets live there. This page turns each rule into a check. The only things it adds are the mechanics of running a check: what to quote, what is exempt, and which check owns a finding.

## How to run it

1. Read the whole file once without judging it. You need to know what it covers before you can say what it lacks.
2. Decide which kind of file it is, from the table under rule 10 in `../SKILL.md`.
3. Walk the ten checks below. For each, write `pass` or `fail`. A file with one failing sentence fails the check. Quote the sentence and give its line number.
4. Write the report in the shape at the end. Findings, not a score. A number hides which line to fix.

Be adversarial. Look for the sentence that fails, not the reasons the file is fine. A review that runs a rule finds more than one that reads it: check 9 has you pick three rules and ask what you would do in a case the author did not list. If the answer is "I would guess", the rule fails check 1 or check 9.

Table cells and headings are exempt from the sentence checks in check 4. A label is the right form there.

## The checks

### 1. Reason beside the rule

Fail when a rule states what to do and neither the same sentence nor the next says why, under the two allowances rule 1 gives. Quote the bare rule. A reason that lives in another file, reached by a link, passes only if the link is on the same line.

Do not fail a hard limit for lacking a reason. A hard limit sits under its marked heading and needs none. Check 7 covers whether it is marked.

### 2. One home per fact

Fail when the same rule appears in this file and in another file it links to or imports, in full. Quote both. A short restatement that exists only to point ("commit rules: see X") passes. A worked example may show a rule, and a rule may point at it. It fails only when its commentary restates the rule's reason in full instead of pointing back. Two files that state the same rule differently is the worst case. Quote both and say which one the agent will follow.

You may need to open the linked files. Do so. A review that reads one file cannot check this rule.

### 3. Pointer over paste, sized to load frequency

Two tests, and the kind decides which apply.

- For a file loaded every turn: fail when it holds detail that only some tasks need, or when it pastes content that also lives at a path it could point to. Quote the block and name the path it should point to. Count `@import` lines as content, not pointers, as rule 3 says.
- For every kind: fail when the file states a rule the agent already follows without it. Apply the deletion test from rule 3. You cannot run it by reading, so answer it as a judgement: would a current model, given the task and the rest of the file, do this anyway? If yes, the line costs tokens for nothing.

Measure the file against the budget for its kind in the table under rule 10 of `../SKILL.md`. Background the task does not need, such as attribution or provenance, is a check 10 finding, not a check 3 finding.

### 4. Plain imperative sentences

Fail on any of these. Quote the sentence.

- A sentence with two instructions joined by "and" or a semicolon.
- Passive voice where the actor matters ("tests should be run" hides who runs them).
- A term used before it is defined, when a cold reader would not know it.
- Two names for one thing in the same file, or one word carrying two meanings.
- A fragment, an arrow chain, or a compressed label standing in for a sentence.

Long is not a failure. Unclear is.

### 5. Show, do not describe

Fail when a file describes a shape in prose or a table, and the shape is what the reader must produce. A folder layout, a file template, a message format, a command form, a section the reader must write. Quote the description and say what a filled example would replace it with.

Pass when the file gives one filled example with guidance inside it, or points at one by name. Pass also when the shape is not the point and prose is enough.

### 6. No history

Fail on any sentence that describes a former state. "Used to", "previously", "no longer", "was renamed from", "old name", "once did". Quote it. A reason that says how something changed is history too. The fix is to state the current fact and delete the comparison.

A changelog section fails. A version number in frontmatter passes.

### 7. Reasons over emphasis

Fail when a sentence uses ALL-CAPS MUST, NEVER, ALWAYS, CRITICAL or IMPORTANT and is not a hard limit. Quote it. A hard limit, as rule 7 in `../SKILL.md` defines it, passes when it sits once under a heading that marks it and its exceptions are written into it. It fails when it sits outside that heading, or when it is repeated elsewhere in the file for emphasis.

Fail also when a limit is one the owner would grant an exception to. Rule 7 says why that makes it guidance.

### 8. Freedom level is explicit

Fail when the file does not say what its agent decides alone, what it decides and records, and what stops it to ask. The agent is the reader the file is written for, as rule 10 lists them. Fail also when a tier's name and its instruction disagree, for example a "stop and ask" tier that tells the agent to carry on. Quote the section that comes closest, or say there is none.

For a brief this is the most common failure, and rule 8 says what it costs.

For a reference file, mark it `n/a`. Rule 8 says why a reference needs no tiers.

### 9. The cold-read test

Pick three rules in the file. For each, ask "but what exactly?" as a reader with no context. Fail if any of the three leaves you guessing at a file, a command, a threshold, a name or an action. A rule that contradicts itself fails here and under the check whose rule it breaks. Quote the rule and write the question you could not answer. Name the three rules under this check whether it passes or fails, so the reader can see what was tested.

Prefer the rules that matter most to the file's purpose, not the easiest three.

### 10. Matched to its reader

Fail when the file's length or context does not fit its kind. Quote the mismatch. A block that already failed check 3 is not listed again here.

- An always-on file that carries a workflow: the workflow belongs in a skill.
- A skill body that carries background the task does not need: it belongs in a reference. A skill body with no workflow at all fails too, because the reader triggered it to do something.
- A brief that assumes the reader saw the conversation: it must carry the parts the table under rule 10 lists.
- A reference that is a list of pointers: a reference is where the detail lives.

## Report shape

Write the report in this form. One line per check. Findings under it, each with the quoted sentence and its line number. A passing check may carry one line saying what was tested. The line count includes frontmatter.

````markdown
# Review: <file path>

Kind: <CLAUDE.md | AGENTS.md | rules file | skill body | reference | system prompt | brief>
Lines: <count>  Budget: <from the table under rule 10>

| Check | Result |
|---|---|
| 1 Reason beside the rule | pass / fail |
| 2 One home per fact | pass / fail |
| 3 Pointer over paste, sized to load frequency | pass / fail |
| 4 Plain imperative | pass / fail |
| 5 Show, do not describe | pass / fail |
| 6 No history | pass / fail |
| 7 Reasons over emphasis | pass / fail |
| 8 Freedom level explicit | pass / fail / n/a |
| 9 Cold-read test | pass / fail |
| 10 Matched to reader | pass / fail |

## Findings

### Check N: <name>
- Line <n>: "<quoted sentence>". <what fails, in one sentence>. Fix: <one sentence>.

## Verdict
<One sentence: ready, or the one thing that must change before it is.>
````

A review with no findings says so. Check 9 still names the three rules it cold-read. "Clean" without that list is not a review.
