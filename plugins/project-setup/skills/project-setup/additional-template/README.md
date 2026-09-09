# additional-template/ — the add-ons

`template/` is the floor every repo starts from. This folder holds the pieces a repo adds later, one at a time, when the user asks for them. A bootstrap never copies from here. An audit never reports a missing add-on as a finding.

Each add-on drops into the repo at the same relative path. Copy it, then make the edits its row names. Record every add-on in `AGENTS.md` in the same change, because the brief is what the next audit compares against.

| Add-on | Path here | What it is | Add it when | After the copy |
|---|---|---|---|---|
| Git hooks | `lefthook.yml` | Staged lint on commit, a `data/` and `logs/` guard on commit, `ctl test` on push. Every hook calls `ctl`. | The second contributor, or CI, or the user asks. | Copy to the root. Add `lefthook = "latest"` to `.mise.toml` `[tools]`. Run `mise install`, then `ctl setup`, which runs `lefthook install`. Add `lefthook` to the `Dev` row of the `Stack` table in `AGENTS.md`. |
| Memory folder | `memory/` | Working rules split into one file per rule set, imported into `AGENTS.md` with `@memory/<file>.md`. | The `Working rules` section of `AGENTS.md` outgrows one screen, or a second rule set (styling, review) needs its own file. Until then the rules live in `AGENTS.md`. | Copy to the root. Move the `Working rules` bullets from `AGENTS.md` into `memory/rules.md`. Replace the section body with `@memory/rules.md` and the line "Read `memory/` before any change." Add a row to `memory/README.md` for each file. |
| Browser suite | `apps/example-single-web-app-vite/e2e/` | One Playwright smoke spec. `ctl test e2e` runs it against a built stack on a throwaway `DATA_DIR`. | There is a user flow worth protecting. | Copy into the frontend that owns `/`, as `e2e/`. Add `@playwright/test` to that app's devDependencies and `"test:e2e": "playwright test"` to its scripts. Add `e2e` to `RUNGS` in `scripts/gate/all.sh` and to the `Gate ladder` row in `AGENTS.md`. |

Ladder rungs beyond the floor (`dead`, `audit`, `build`) are not add-ons. Their files already ship in `scripts/gate/`. Switching one on is one name in `RUNGS` and one in `AGENTS.md`; `10b_static-checks.md` says when each is usually earned.

Rules that hold for every add-on:

- **Adding is the user's call.** The skill may recommend one and say why. It never installs one on its own, because each add-on is a cost the user carries on every commit.
- **Never removed once earned.** An installed hook, rung or suite stays. A repo that outgrows a rule tightens it; it does not drop it.
- **One home.** The add-on lives here until installed, then in the repo. The rule page names the path under this folder; the repo names its own path.
