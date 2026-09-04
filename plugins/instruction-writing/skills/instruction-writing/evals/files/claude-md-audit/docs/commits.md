# Commit messages

Use the conventional commits form: `type(scope): summary`. A machine reads the type and scope to build the changelog, so the form has to be exact.

- Types: feat, fix, docs, refactor, test, chore. A breaking change adds `!` after the type.
- Scope is the top-level folder: `api`, `web`, `infra`. A commit that touches both `api` and `web` uses `all`.
- Summary: imperative, lower case, no full stop, under 72 characters.
- Body: why, not what. Wrap at 72. Name the ticket if there is one.
- Footer: `Closes #NNN` when the commit closes an issue. The tracker reads it.

Sign off with `-s`. The DCO check fails a PR without it.

Squash fixup commits before you open the PR. Reviewers read one commit per change.

Do not commit anything under `dist/`. It is a build output and the CI rebuilds it.
