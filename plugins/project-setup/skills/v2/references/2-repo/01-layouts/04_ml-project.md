# Layout 04 — ML project

Owns the **ML repo shape**: a uvenv-driven global-Python training/experiment repo — `requirements.txt`, notebooks, per-experiment configs, gitignored data/models/outputs. Deliberately different from an app repo.

## When it fits

- Model training, fine-tuning, experiments; notebooks are first-class.
- Heavy dependence on global ML libs (torch, transformers, jax, accelerate, datasets, peft, …) shared across many experiment repos.
- May or may not produce a deployed inference service — if it does, that service is a **separate app project** (Layout 01 or 02), not this repo.

## Tree

```
my-ml/
├── .env                            # API keys / tokens (gitignored)
├── .env.example
├── .mise.toml                      # python only (single version)
├── requirements.txt                # human-authored, broad ranges, with comments
├── uvenv-name                      # plain file naming the env (e.g. "ml-recommender")
├── ctl                             # dispatcher — task subcommands
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

Note the shape-defining choices: an `apps/<project>/src/` package (ML wrappers are importable, so src-layout is fine here — unlike a run-service app), first-class `notebooks/`, per-experiment `configs/<experiment>.yaml` (no single `config.yaml`), and gitignored `data/` `models/` `outputs/` with `.gitkeep`s and a data README.

## Python & dependency flow

`requirements.txt` (broad ranges, not `uv.lock`) plus a shared **uvenv** named global env — the reasoning (why ML differs from the app `pyproject.toml` + `uv sync` flow), the `requirements.txt` shape, the `uvenv-name` file, the uvenv commands, and `ctl` activating the env at the start of every subcommand are all owned by `references/3-app/02-backend/03_ml-python-flow.md`. Don't restate them here; the tree above shows only where those artifacts sit.

## `ctl` subcommands

The repo's task interface (the wrapper activates the uvenv from `uvenv-name` first — see ml-python-flow):

```
ctl train --config <path>        # python apps/<project>/src/train.py --config <path>
ctl eval --run <run-id>          # evaluation
ctl serve                        # optional inference
ctl nb                           # start jupyter / notebook server in the right env
ctl data-prep                    # one-shot data prep
ctl clean
ctl help
```

## What's NOT here (shape negatives)

- No `docker/` — ML usually runs on bare metal with GPUs.
- No `infra/` — same reason.
- No frontend — a UI is a separate app project.
- No `config.yaml` — `configs/<experiment>.yaml` per-experiment is the pattern.

## Cloud-aware repo additions

Layout 04 defines the **repo shape**; *how* training, sweeps, inference, and remote dev actually run on cloud GPUs is owned by the `references/2-repo/07-ml-orchestration/` set (start at `references/2-repo/07-ml-orchestration/00_custom-orchestrator.md`). If the user opts into cloud GPUs, add:

```
my-ml/
└── scripts/
    └── cloud/                      # thin wrappers over the provider CLI / custom orchestrator
        ├── remote-dev.sh
        ├── train-spot.sh
        ├── sweep.sh
        ├── eval.sh
        ├── serve.sh
        ├── status.sh
        ├── teardown.sh             # safety net — stop all runs
        └── wait-for-run.sh
```

When `/ps-setup` runs for an ML project, after the standard Layout 04 questions also run the cloud-orchestration batch in `references/01_question-flow.md`.

## Escalation

- Need exact reproducibility or shipping a model server → migrate inference to a separate app project (Layout 02) with `pyproject.toml` + `uv.lock`, importing model artifacts from this repo. The graduation criteria are owned by `references/3-app/02-backend/03_ml-python-flow.md`.

## See also

- `references/3-app/02-backend/03_ml-python-flow.md` — requirements.txt vs pyproject, uvenv, `uvenv-name`, graduation criteria
- `references/2-repo/07-ml-orchestration/` — cloud GPU orchestration (`scripts/cloud/` wrappers, spot + checkpoints, remote dev, inference autoscaling, ML CI/CD)
- `references/5-examples/04_ml-training-project.md` — worked example: uvenv, configs/, scripts/cloud/, checkpoints
- `references/2-repo/01-layouts/02_multi-app-monorepo.md` — the app repo you graduate an inference service into
