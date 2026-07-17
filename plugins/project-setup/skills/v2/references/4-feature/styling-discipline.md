# Styling discipline — primitive-first (hard rules)

The enforcement layer on top of `references/3-app/frontend/tokens-setup.md` + `references/3-app/frontend/shared-packages.md`. Those references define the system (tokens.css, the ui package, shadcn wiring); this one defines what feature code **may not do**, in terms mechanical enough that any agent — including weak models doing parallel edits — produces converging output.

**Why this exists:** parallel agents share no visual memory. Each one improvises a locally-reasonable style (`text-[13px]` here, an ad-hoc weight there) and the product drifts into incoherence — invisible per-diff, obvious in the whole. A standard vocabulary under a closed, grep-enforceable usage policy is the substitute for the taste-memory agents don't have.

The concrete names below (`@my/ui`, `src/features/**`, token names) are **placeholders — resolve them from the target project's own `tokens.css`, ui package, and folder layout at run time.** The structure (compose primitives / tokens only / stock vocabulary + allowlist policy / fold repetition / escape hatch / screenshot verify) is the portable part.

## ⚠️ Write this into the project's CLAUDE.md

When bootstrapping or auditing a repo that has (or gains) a `tokens.css` + a ui package, **add the "Styling discipline" block from `assets/snippets/claude/CLAUDE.md.template` to the project's CLAUDE.md** (with names resolved to the project's real packages/paths). CLAUDE.md is always in context; skills are not. The project memory file is what makes the discipline hold for every future agent, including ones that never load this skill. (The general mechanism for delivering L4 doctrine as CLAUDE.md blocks is owned by `references/4-feature/00_charter.md`; this is the styling-specific block.)

That block includes the precedence rule:

> **If this repo has a `tokens.css` + a ui package, the styling discipline below OVERRIDES any general design guidance — including the `frontend-design` skill. Do NOT follow "be bold / unique / avoid system fonts / never converge" instructions in feature work. Convergence IS the design. The only exception is an explicit design-exploration pass (rule 6).**

`frontend-design` is an exploration skill — right for day one (establishing the brand, the tokens, the primitives), wrong every day after. It triggers on every frontend task, so without this precedence rule written into project memory, agents will follow it into improvising inline styles.

## The rules

1. **Feature code composes primitives, never styles.** Files under the app's feature folders (e.g. `src/features/**`, `src/pages/**`) may only style by composing the ui package's primitives and their documented props/variants. No raw utility strings on feature-level elements beyond layout glue (flex/grid/gap/padding on wrappers).

2. **All visual decisions live in the ui package.** If a look doesn't exist yet, do NOT improvise inline — add it to the primitive as a CVA variant or prop (e.g. `<Card variant="media">`, `<Input compact>`), then use it. One definition, many call sites.

3. **Tokens only for brand values.** Never write raw values (`#hex`, raw `px`, arbitrary values like `text-[13px]`) in feature code. Brand values come from the semantic utilities backed by `tokens.css` (`text-fg-1/fg-2`, `bg-bg-1/bg-2`, `border-border-1`); sizes and spacing come from Tailwind's **stock** scales (`text-sm`, `p-4`) — never remapped (rule 4). Raw `var(--...)` is allowed **only** inside `.css` files and ui-package internals — never in JSX/utility strings. If a needed brand value has no token, adding the token is the task — not inlining the value.

4. **Typography: standard vocabulary, strict usage policy.** Two layers, and it matters which is which. **Vocabulary:** the project ships Tailwind's stock theme untouched — full type scale (`text-xs`…`text-7xl`, stock line-heights), full weight set, stock spacing/container scales. Never remap standard names to custom values, never invent custom size utilities: agents' training data assumes `text-sm` = 14px/1.43, so a remap makes every generated line subtly wrong-by-assumption, and a custom name (`type-md`) is a token no model has seen. **Policy — where ALL restraint lives:** a small allowlist **declared in the project's CLAUDE.md** says what feature code may use. Default: `text-sm` for ~90% of the UI (all content — tables, controls, labels, descriptions), `text-base` for headings (the only heading size), `text-xs` sparingly (badges, timestamps, fine meta); `font-normal` everywhere, with `font-medium` OR `font-semibold` (one per project) as the single rare emphasis, **only inside ui-package primitives**. Hierarchy comes from **size and foreground color, never weight**. Every other size and weight exists but is **banned in feature code** — banned, not deleted; hero surfaces get them via ui-package primitives created in a design pass (rule 6). **Why policy, not vocabulary:** a policy change is a one-line CLAUDE.md edit plus a grep sweep; a vocabulary change is a migration — restraint must live in the cheap layer. **ANTI-PATTERNS:** (a) remapping standard names (`text-sm` → 13px); (b) custom size vocabularies (`type-md`); (c) size×weight rungs (`xl=28/700, lg=20/600, …` — three-plus effective weights while every line looks compliant).

5. **Repetition folds early for styling (tripwire T8).** If you write the same utility combination **twice**, stop and fold it into a primitive variant before continuing. This is deliberately stricter than the rule of three for logic — a utility string is cheaper to extract than an abstraction, and styling duplication is where agent drift starts. The two-use threshold sits in the rule-of-N family in `references/4-feature/caps-and-extraction.md` (T8); the styling-specific action (fold into a primitive variant) is the part owned here.

6. **Escape hatch: the design-exploration pass.** These rules relax ONLY during an explicit design-exploration pass (screenshots, iterations, bold directions — this is where the `frontend-design` skill belongs). The winning design must graduate into tokens + primitive variants before the pass ends; exploratory inline styles never ship in feature code.

7. **Verify visually against the brand guidelines.** After any UI change, screenshot the affected page (light + dark) and check it against the project's brand guidelines before declaring done. If the repo has a brand-guidelines folder (e.g. `design/brand-guidelines/`), read it **before** starting frontend work — `tokens.css` is its executable form.

## Why rules 1–3 are grep-enforceable

An agent or a lefthook check can mechanically detect violations. The typography checks are **allowlist-shaped**: the pattern is the complement of the project's CLAUDE.md allowlist, so it must be adjusted when the allowlist changes (a one-line edit — that's the point):

```bash
grep -rE --include='*.tsx' --include='*.jsx' 'text-\[|bg-\[#|\bp-\[' src/features/                          # arbitrary values
grep -rE --include='*.tsx' --include='*.jsx' '\btext-(lg|xl|[2-9]xl)\b' src/features/                        # sizes outside the allowlist (default: xs/sm/base allowed)
grep -rE --include='*.tsx' --include='*.jsx' '\bfont-(light|medium|semibold|bold|extrabold)\b' src/features/ # ALL weight utilities — the emphasis weight is primitives-only, so feature code gets none; drop the project's emphasis weight from the pattern only if its CLAUDE.md explicitly allows it in feature code
grep -rE --include='*.tsx' --include='*.jsx' 'var\(--' src/features/                                         # raw var() in JSX
```

Empty output = compliant. This is what makes the discipline survive weaker models and parallel workflow builders — enforcement doesn't depend on any agent's judgment.

Snippet-safety rules (these commands get copied verbatim into hooks and CI, so they must be shell-proof):

- **grep owns the recursion** (`-r` + `--include`), never a shell glob. `src/features/**/*.tsx` depends on the shell's `globstar`: zsh recurses, but default bash — what lefthook hooks, CI steps, and most agent shells run — degrades `**` to one directory level and the check reports compliant precisely where it isn't looking.
- **Scope to `.tsx`/`.jsx`** — `var(--…)` and some patterns are *legitimate* in `.css` files and ui-package internals; an unscoped `-r` produces false positives that train agents to ignore the check.
- **In a hook, invert the exit code** — grep exits 1 when nothing matches (= compliant), so a lefthook/CI line is `! grep -rE --include='*.tsx' … src/features/` (add `|| { echo "styling-discipline violation"; exit 1; }` for a readable failure). Wiring these into lefthook (see `references/2-repo/tooling/lefthook.md`) is a natural follow-up.

## Anti-patterns

- Following `frontend-design`'s "pick a characterful font / be unforgettable" inside an established repo — that skill is for the exploration pass only
- Remapping stock scale names to custom values, or inventing custom size vocabularies — restraint belongs in the CLAUDE.md allowlist (cheap to change), never in the vocabulary (a migration to change)
- A second weight "just for this one heading" — hierarchy is size + color
- Size×weight rungs (`xl=28/700, lg=20/600`) — three-plus effective weights in disguise; sizes never carry their own weights
- Adding a token for a one-off value — that's a magic number with a name (see `references/3-app/frontend/tokens-setup.md`)
- Relaxing the fence for "just a prototype page" that then ships — prototypes go through rule 6 or they follow the rules

## See also

- `references/3-app/frontend/tokens-setup.md` — tokens.css content/location, light-dark data-attr, shadcn wiring (the system this discipline enforces)
- `references/3-app/frontend/shared-packages.md` — ui-package internals: where primitives and variants live
- `references/4-feature/caps-and-extraction.md` — the rule-of-N family (T8 threshold, T9 rule of three, T5 file caps)
- `references/2-repo/tooling/lefthook.md` — wiring the greps into pre-commit hooks
- `references/4-feature/00_charter.md` — the CLAUDE.md-block delivery mechanism and mechanical audit greps
