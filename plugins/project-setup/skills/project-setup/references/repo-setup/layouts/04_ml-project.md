# Layout 04 — ML project

uvenv-driven global Python env, `requirements.txt`, experiments + notebooks + training scripts. **Different from app projects on purpose.**

## When it fits

- Model training, fine-tuning, experiments
- Heavy dependence on global ML libs (torch, transformers, jax, accelerate, datasets, peft, …) shared across experiments
- Notebooks are first-class
- May or may not produce a deployed inference service (if it does, that's a separate app project)

## Tree

```
my-ml/
├── .env                            # API keys (OPENAI, ANTHROPIC, HF_TOKEN, WANDB)
├── .env.example
├── .mise.toml                      # python only (single version)
├── requirements.txt                # human-authored, broad ranges, with comments
├── uvenv-name                      # plain file containing the env name (e.g. "ml-recommender")
├── ctl                             # ctl — task subcommands
├── apps/                           # code in a package folder, never loose in root
│   └── <project-name>/
│       ├── src/<package>/          # ML utilities/wrappers are an importable lib → src-layout ok
│       └── tests/
├── notebooks/                      # exploratory notebooks
│   ├── 01_data-exploration.ipynb
│   ├── 02_baseline.ipynb
│   └── 03_ablations.ipynb
├── configs/                        # per-experiment hyperparameters
│   ├── baseline.yaml
│   ├── ablation-A.yaml
│   └── ablation-B.yaml
├── scripts/
│   ├── train.sh
│   ├── eval.sh
│   ├── serve.sh                    # optional inference entrypoint
│   └── data-prep.sh
├── data/                           # gitignored (large)
│   ├── raw/.gitkeep
│   ├── processed/.gitkeep
│   └── README.md                   # where the actual data lives + how to fetch
├── models/                         # gitignored (checkpoints)
│   └── .gitkeep
├── outputs/                        # gitignored (logs, plots, eval results)
│   └── .gitkeep
├── docs/                           # optional
├── .claude/                        # empty initially
├── CLAUDE.md
└── README.md
```

## Why `requirements.txt` not `pyproject.toml`?

- ML libs are **global by nature**. You install torch once in a uvenv and reuse it across 5 experiment repos. Lockfiles per-repo would force 5 copies.
- Pip-resolves are tolerant — appropriate for ML where exact pin chains are brittle and broad version ranges work fine.
- Notebook dev flow benefits from `pip install` (or `uv pip install`) in an active env, not `uv sync` against a project lockfile.

If you later want to ship the trained model as a service: spin up a **separate app project** (Layout 01 or 02) with `pyproject.toml` + `uv.lock`, and import the model artefacts.

## uvenv flow

```bash
# one-time, per env (shared across experiment repos)
uvenv create --python=3.13 -n ml-recommender
uvenv activate ml-recommender
uvenv install -r requirements.txt          # bulk install
uvenv install torch transformers accelerate

# inside a project
uvenv activate ml-recommender
ctl train --config configs/baseline.yaml
```

The repo's `uvenv-name` file tells `ctl` which env to activate.

## `ctl` subcommands

```
ctl train --config <path>        # python apps/<project>/src/train.py --config <path>
ctl eval --run <run-id>          # evaluation
ctl serve                        # optional inference
ctl nb                           # start jupyter / vscode notebook server in the right env
ctl data-prep                    # one-shot data prep
ctl clean
ctl help
```

The wrapper assumes uvenv is active (or activates it from `uvenv-name`).

## What's NOT here

- No `docker/` — ML usually runs on bare metal with GPUs
- No `infra/` — same reason
- No frontend — if there's a UI it's a separate app project
- No `config.yaml` — `configs/<experiment>.yaml` per-experiment is the pattern

## dstack integration

If running training on remote GPUs (dstack / runpod / etc.), add:

```
my-ml/
├── .dstack/
│   └── profiles.yml
└── <experiment>.dstack.yml       # the run spec
```

The `dstack` plugin in this marketplace covers the rest.

## Real-world reference

No registered ML example yet — propose the conventions on their own merits.

## Escalation

- Need reproducible builds with exact deps → move to `pyproject.toml` + `uv.lock` (Layout 01)
- Ship inference as a service → add an app project (Layout 02), import model from this one

## See also — cloud orchestration

Layout 04 defines the **repo shape**. For **how training, inference, sweeps, and remote dev actually run on cloud GPUs**, see `references/architecture/ml-orchestration/`:

- `overview.md` — when to reach for cloud orchestration; tools recognised (dstack / SkyPilot / custom)
- `dstack.md` — default; composes with the dstack sibling plugin's skill
- `skypilot.md` — alternative; multi-cloud + k8s strengths
- `custom-orchestrator.md` — placeholder for a future bespoke tool
- `spot-instances-and-checkpoints.md` — surviving spot preemption
- `inference-autoscaling.md` — long-running inference, scale up/down, auto-redeploy
- `remote-dev-ssh-vscode.md` — one-command remote GPU box with SSH + VS Code Remote
- `agent-ssh-access.md` — running Claude (or another agent) on or via the remote
- `cicd-for-ml.md` — cheap/medium/expensive pipeline tiers for ML

When `/ps-setup` runs for an ML project, after the standard Layout 04 questions, also run Batch 7 in `01_question-flow.md` (cloud orchestration questions).

## Cloud-aware repo additions

If the user opts into cloud orchestration, add to the layout:

```
my-ml/
├── tasks/                          # *.dstack.yml configs per job
│   ├── dev.dstack.yml              # remote dev environment
│   ├── train.dstack.yml
│   ├── sweep.dstack.yml
│   ├── eval.dstack.yml
│   └── serve.dstack.yml
├── .dstack/profiles.yml            # backend / GPU type / max price
└── scripts/
    └── cloud/
        ├── remote-dev.sh
        ├── train-spot.sh
        ├── sweep.sh
        ├── eval.sh
        ├── serve.sh
        ├── teardown.sh             # safety net — `dstack stop --all -y`
        └── wait-for-run.sh
```

If SkyPilot instead, replace `tasks/` with `sky/<task>.yaml` and `.dstack/profiles.yml` with the SkyPilot equivalent.
