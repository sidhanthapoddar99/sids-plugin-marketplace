# Review — the passes a person or an agent runs on approval

A review pass is a check that needs judgement: a second party reads, runs or looks at a frozen state and decides. A second party is a person, or a model other than the one that wrote the change. Nothing on this page is a rung. A rung is automated and lives in `10b_static-checks.md` or `10c_dynamic-tests.md`. An agent checking its own change, such as the screenshot after a UI edit in `AGENTS.md` § Styling, is a working rule, not a pass, because it has no second party.

Two files share the work. This page is the catalogue: every pass the skill knows, with the moment to offer it and the tool that runs it. `AGENTS.md` § Review passes is the choice: which passes this repo runs and on what standing rule. The catalogue is the same for every repo, so it lives here once. The choice differs per repo, so it lives in the brief.

## Who starts a pass

A pass runs on the user's approval, never on a trigger, because each pass costs a second party's time and the user owns that budget. The "Offer when" column below says when to raise it. Raise it in one line with the reason, then wait. `AGENTS.md` § Review passes says how a standing rule stands in for that yes.

A stage is a unit of the plan that ends in a working state. The tracker defines it when the project has one. Without a tracker, it is a milestone the user names.

## The passes

| Pass | Industry name | We call it | Offer when | Runs through |
|---|---|---|---|---|
| A second model reads and runs the change | Independent code review | the adversarial review | A stage closes. | A second model in its own shell, for example Codex through the `codex` plugin. It runs the code; reading alone misses what only a run shows. |
| A peer reads the pull request | Peer review | the PR review | A second contributor exists. | The pull request on the repo's host, such as GitHub. The adversarial review does not replace it, because a colleague and a model catch different things. |
| The repo is compared against the brief | Architecture review | the audit | A stage closes, or the user asks whether the repo still follows the rules. | This skill, `SKILL.md` § Auditing. `ctl check` is its first row. |
| A person tries to break a frozen build | Exploratory testing, manual QA | the frozen-build pass | A stage closes. | `ctl build save`, then `ctl build start`. A person, or an agent driving the app through Playwright. A frozen build cannot change under the tester. `09_production.md`. |
| Threats are walked before going public | Threat modelling, security review | the security review | The first public deploy is near, or a new identity plane or external integration lands. | `07_security.md` is the checklist. Record each answer in `AGENTS.md`. |
| Licences of dependencies are checked | Licence compliance | the licence review | A package is about to be published, or a customer asks. | `bunx license-checker`, `uv pip list --format json` with the licence field, `cargo deny check licenses`. |
| The agent brief is checked | no common name | the instruction review | `AGENTS.md` or `CLAUDE.md` changed. | The `instruction-writing` skill's rubric, run by a fresh agent. |

## Rules

- A pass runs against a frozen state: a commit, a frozen build, a tagged image. A working tree that is still changing gives findings nobody can reproduce.
- A finding names the file and the line, the same as a rung, because "the auth code looks off" cannot be fixed or closed.
- Findings are written down where they outlive the reply: the tracker when there is one, otherwise the wrap-up. A finding that lives only in chat is lost at the next session.
- When a pass finds a class of bug a linter could catch, the fix is the lint rule in `10b_static-checks.md`, so the pass keeps its time for what needs judgement.
- Mutation testing is not done. It costs hours and finds little that an adversarial review and a frozen-build pass do not.

## Reviewing CTL lifecycle changes

For a setup, storage, process or deployment change, compare the guide with executable behavior. Use `tests/ctl/README.md` for the tooling suite. Report separately what recording shims simulated, what real child processes exercised, and what ran against actual Cargo or Compose; a warm developer machine does not prove a fresh installation works.

| Boundary | Evidence to inspect |
|---|---|
| Source discovery | A nested source package is included; dependency, build and vendor decoys are excluded; Cargo workspace members do not trigger duplicate fetches. |
| Toolchain | A minimal-PATH fixture exposes installed tools only after activation; install, activation and dependency failures return nonzero; one app does not require unrelated runtimes. |
| Credentials | Only explicitly listed local credentials are generated; supplied values and reruns are stable; required provider blanks fail; logs contain names rather than credential values. |
| Storage | Relative, absolute and space-containing paths work from another current directory; setup, logs, ownership records and snapshots agree without creating unwanted default directories. |
| Development | Probe failure, early exit, timeout and interruption clean the invocation's process groups and preserve unrelated processes; a pre-existing listener must prove readiness. |
| Production | Build failure makes no activation call; selected dependencies are included; successful one-shots and failed long-running services are distinguished; readiness is bounded and failure does not imply rollback. |
| Runtime dispatch | Current-project container selection, explicit host fallback, argument boundaries, TTY policy and nonzero exit propagation hold. |
| Restore | Missing or invalid input causes no mutation; archive validation precedes every drop/create; active dependents are refused. Archive listing is not proof that the restore will succeed, and the guard is not a writer lock. |
| Optional WASM | Only WASM projects install targets and packaging tools; target checks use the selected toolchain; release builds, serialized source watching and compatibility-aware activation follow `06_backend.md`. |
