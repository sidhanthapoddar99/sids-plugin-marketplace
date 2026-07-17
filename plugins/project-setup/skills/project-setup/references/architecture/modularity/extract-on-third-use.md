# Extract on third use — the rule of three

When you see the same pattern repeating, **count uses before extracting**:

- **1 use** — inline
- **2 uses** — duplicate (cheap; might diverge)
- **3 uses** — extract a shared helper

Pre-emptive abstraction is more expensive than duplication. Three similar lines is better than a premature abstraction.

## Why

- **Premature abstraction has a discovery cost** — readers must follow it to understand the call site
- **The "abstraction" often doesn't fit** — the third use reveals which parameters actually generalise
- **Duplication is reversible** — abstraction is harder to undo

## In practice

| Situation | Action |
|---|---|
| `if user.is_admin or user.is_owner` appears once | inline |
| Same condition in two functions | inline both — they might diverge |
| Same condition in three functions across two files | extract `def can_manage(user) -> bool` |

The extract should be **named for what it means**, not for what it does mechanically.

## What counts as "the same"

- Same logic + same shape (not just syntactic similarity)
- Same business meaning ("a user can manage this resource" — not "two if-checks")
- Not just same return type — a `bool` from two different rules should stay two functions

## What does not count

- Boilerplate that the framework demands (FastAPI route signatures, React hook structure) — that's the framework, not your duplication
- Similar shapes with different meaning — leave separate
- Sequential lines in two files that happen to use the same APIs but for different reasons

## Counter-rule: extract earlier when

- The pattern is **non-obvious** (clever algorithm, tricky regex) — extract on first use with a name, so callers don't have to understand
- The pattern is **dangerous** (security-sensitive crypto, parsing untrusted input) — extract on first use to centralise review
- The pattern is **owned by a different layer** (DB query, HTTP call) — extract immediately into the appropriate module
- The pattern is **a styling utility combination** — fold into a primitive variant on the **second** use (see `architecture/frontend/styling-discipline.md`); utility strings are cheaper to extract than logic abstractions, and styling duplication is where visual drift starts

## Anti-patterns

- "I might need this later" — wait
- Extract on second use "just to be safe" — second uses often diverge
- Helper functions named `process_data`, `handle_thing` — names that don't mean anything
- Generic "framework" code in your repo that you wrote — frameworks are full-time work; you have a job
- Refusing to extract on the 4th, 5th, 6th use — at some point duplication itself becomes the problem

## Real-world reference

- The one-line form for a project CLAUDE.md: *"Three usages of similar code is the trigger for shared helpers; one or two is fine to inline."*
