# Styling discipline — primitive-first (hard rules)

The enforcement layer on top of `design-tokens.md` + `shared-ui-package.md` + `shadcn-tailwind.md`. Those references define the system; this one defines what feature code **may not do**, in terms mechanical enough that any agent — including weak models doing parallel edits — produces converging output.

**Why this exists:** parallel agents share no visual memory. Each one improvises a locally-reasonable style (`text-[13px]` here, an ad-hoc weight there) and the product drifts into incoherence — invisible per-diff, obvious in the whole. A closed, grep-enforceable vocabulary is the substitute for the taste-memory agents don't have.

The concrete names below (`@my/ui`, `src/features/**`, token names) are **placeholders — resolve them from the target project's own `tokens.css`, ui package, and folder layout at run time.** The structure (compose primitives / tokens only / closed ladder / fold repetition / escape hatch / screenshot verify) is the portable part.

## ⚠️ Write this into the project's CLAUDE.md

When bootstrapping or auditing a repo that has (or gains) a `tokens.css` + a ui package, **add the "Styling discipline" block from `assets/snippets/claude/CLAUDE.md.template` to the project's CLAUDE.md** (with names resolved to the project's real packages/paths). CLAUDE.md is always in context; skills are not. The project memory file is what makes the discipline hold for every future agent, including ones that never load this skill.

That block includes the precedence rule:

> **If this repo has a `tokens.css` + a ui package, the styling discipline below OVERRIDES any general design guidance — including the `frontend-design` skill. Do NOT follow "be bold / unique / avoid system fonts / never converge" instructions in feature work. Convergence IS the design. The only exception is an explicit design-exploration pass (rule 6).**

`frontend-design` is an exploration skill — right for day one (establishing the brand, the tokens, the primitives), wrong every day after. It triggers on every frontend task, so without this precedence rule written into project memory, agents will follow it into improvising inline styles.

## The rules

1. **Feature code composes primitives, never styles.** Files under the app's feature folders (e.g. `src/features/**`, `src/pages/**`) may only style by composing the ui package's primitives and their documented props/variants. No raw utility strings on feature-level elements beyond layout glue (flex/grid/gap/padding on wrappers).

2. **All visual decisions live in the ui package.** If a look doesn't exist yet, do NOT improvise inline — add it to the primitive as a CVA variant or prop (e.g. `<Card variant="media">`, `<Input compact>`), then use it. One definition, many call sites.

3. **Tokens only.** Never write raw values (`#hex`, raw `px`, arbitrary values like `text-[13px]`) in feature code. Use the semantic utilities backed by `tokens.css` (`text-fg-1/fg-2`, `bg-bg-1/bg-2`, `border-border-1`, `text-sm/base/lg/xl`). Raw `var(--...)` is allowed **only** inside `.css` files and ui-package internals — never in JSX/utility strings. If a needed value has no token, adding the token is the task — not inlining the value.

4. **Typography ladder is closed.** Four sizes — `text-sm / text-base / text-lg / text-xl` — and **one weight throughout**. Hierarchy comes from **size and color**, not weight. Exactly one `text-xl` per screen (the page title); section/card titles `text-lg`; body and controls `text-base`; table cells, labels, meta, captions `text-sm`. Never add font-weight utilities in feature code; emphasis weight exists as a token for the rare case a primitive absolutely requires it.

5. **Repetition folds early for styling.** If you write the same utility combination **twice**, stop and fold it into a primitive variant before continuing. (This is deliberately stricter than the extract-on-third-use rule for logic — a utility string is cheaper to extract than an abstraction, and styling duplication is where agent drift starts.)

6. **Escape hatch: the design-exploration pass.** These rules relax ONLY during an explicit design-exploration pass (screenshots, iterations, bold directions — this is where the `frontend-design` skill belongs). The winning design must graduate into tokens + primitive variants before the pass ends; exploratory inline styles never ship in feature code.

7. **Verify visually against the brand guidelines.** After any UI change, screenshot the affected page (light + dark) and check it against the project's brand guidelines before declaring done. If the repo has a brand-guidelines folder (e.g. `design/brand-guidelines/`), read it **before** starting frontend work — `tokens.css` is its executable form.

## Why rules 1–3 are grep-enforceable

An agent or a lefthook check can mechanically detect violations:

```bash
grep -rE 'text-\[|bg-\[#|\bp-\[' src/features/       # arbitrary values
grep -rE 'font-(medium|semibold|bold)' src/features/  # weight outside the ladder
grep -rE 'var\(--' src/features/**/*.tsx              # raw var() in JSX
```

Empty output = compliant. This is what makes the discipline survive weaker models and parallel workflow builders — enforcement doesn't depend on any agent's judgment. Wiring these into lefthook (see `repo-setup/tooling/lefthook.md`) is a natural follow-up.

## Anti-patterns

- Following `frontend-design`'s "pick a characterful font / be unforgettable" inside an established repo — that skill is for the exploration pass only
- A second weight "just for this one heading" — hierarchy is size + color
- Adding a token for a one-off value — that's a magic number with a name (see `design-tokens.md`)
- Relaxing the fence for "just a prototype page" that then ships — prototypes go through rule 6 or they follow the rules
