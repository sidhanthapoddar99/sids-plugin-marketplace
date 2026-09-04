# Before and after

Five pairs. Each shows one rule from `../SKILL.md` failing, then the same text passing. Read the pair for the rule you are fixing.

## 1. A bare rule, then the rule with its reason

Rule 1. This one happened. A tracker skill said each subtask entry is one plain link. The site that renders the tracker reads each link's status live. An agent read the first version and added tick marks beside the links, because nothing said why the line had to be bare.

Before:

```markdown
- One plain link per subtask entry.
```

After:

```markdown
- One plain link per subtask entry, nothing beside it. The site reads each
  entry's status live from the file, so any tick, status word or note written
  next to the link is a copy that goes stale.
```

The reason is one sentence. It covers ticks, status words, dates and every other decoration the author did not list.

## 2. A pasted block, then a pointer

Rule 3. This sat in a project CLAUDE.md, loaded every turn. The same twelve lines also lived in the file that owned them.

Before:

```markdown
## Commit messages

Use the conventional commits form: `type(scope): summary`.
Types: feat, fix, docs, refactor, test, chore.
Scope is the app folder name.
Summary is imperative, lower case, no full stop, under 72 characters.
Body explains why, not what. Wrap at 72.
Footer carries `Closes #NNN` when the commit closes an issue.
Never commit generated files under `dist/`.
Sign off with `-s`.
...
```

After:

```markdown
## Commit messages

Follow the form in `docs/commits.md`. Read it before your first commit in a
session. It is short and it is the only copy.
```

The twelve lines now live in one place. The pointer costs one line per turn instead of twelve. The agent opens the file when it needs it. A path in backticks is a pointer. `@docs/commits.md` is not, for the reason rule 3 gives.

## 3. A history aside, then the current text

Rule 6. The first version tells the agent two things and asks it to weigh them.

Before:

```markdown
Run `ctl gate all` before you push. (This used to be `make check`; the
Makefile was removed in 0.4 and some older docs still mention it.)
```

After:

```markdown
Run `ctl gate all` before you push. It is the only gate.
```

Git holds the rename. The old docs are fixed in the old docs, not annotated here.

## 4. Emphasis, then a marked limit and reasoned guidance

Rule 7. The first version shouts at three lines and marks none of them as a limit.

Before:

```markdown
- NEVER push to main.
- ALWAYS run the tests first.
- You MUST NOT edit files under `vendor/`.
```

After:

```markdown
## Hard limits

These have no exception beyond the ones written into them.

- Do not push to `main`. Only the owner merges to a shared branch.

## Guidance

- Run the tests before you push. A red pipeline blocks everyone else's merge
  for the time it takes to notice.
- Do not edit files under `vendor/`. A script copies them in, and your edit is
  overwritten on the next sync. Change the upstream or the script instead.
```

One limit under the heading that marks it, and two rules with their reasons. Rule 7 says why the split matters.

## 5. A brief, shown

Rules 5 and 8. The shape of a brief is the point, so here is one filled in, with the guidance for each part written as a comment under it. A real brief drops the comments.

````markdown
# Brief: rename the `users` table to `accounts`

<!-- Goal first, one paragraph. The reader never saw your conversation.
     Say what done looks like, not how you got here. -->
Rename the `users` table and every reference to it, so the schema matches the
domain name the product now uses. Done means the migration applies, every test
passes, and no file in the repo says `users` where it means the table.

## Files
<!-- Every path the agent needs. It cannot ask you which folder. -->
- `db/migrations/`: add one Alembic migration. Follow `db/migrations/0004_*.py` as the pattern.
- `api/models/user.py`, `api/repositories/user.py`: the two files that name the table.
- Tests: `api/tests/`. Run `pytest -q`.

## Hard limits
<!-- Rules with no exception beyond the ones written in. Few. -->
- Run no git command that writes. The owner commits.
- Change nothing under `web/`. The frontend calls the API, not the table.

## What you decide alone
<!-- Three tiers, so the agent knows when to stop and when not to. -->
- Decide and keep going: the migration's name, variable names, test wording.
- Decide and record in your report: any file outside the list above that you
  had to touch, and why.
- Stop and ask: a foreign key from a table the list does not mention, because
  a wrong cascade deletes data. Report what you found and end the turn.

## Return
<!-- The exact shape of the reply, so the owner can act on it without a
     second run. -->
Reply with: the files changed, the `pytest -q` summary line, and any
decision you recorded.
````

Every part carries its reason. Rule 1 says what that buys.
