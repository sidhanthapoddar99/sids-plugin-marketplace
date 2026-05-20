# Topology 07 — ML project

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
├── dev                             # ./dev — task subcommands
├── apps/                           # always nested, never src/ at root
│   └── <project-name>/
│       ├── src/<package>/          # python package — utilities, model wrappers
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

If you later want to ship the trained model as a service: spin up a **separate app project** (Topology 01 or 02) with `pyproject.toml` + `uv.lock`, and import the model artefacts.

## uvenv flow

```bash
# one-time, per env (shared across experiment repos)
uvenv create --python=3.13 -n ml-recommender
uvenv activate ml-recommender
uvenv install -r requirements.txt          # bulk install
uvenv install torch transformers accelerate

# inside a project
uvenv activate ml-recommender
./dev train --config configs/baseline.yaml
```

The repo's `uvenv-name` file tells `./dev` which env to activate.

## `./dev` subcommands

```
./dev train --config <path>      # python apps/<project>/src/train.py --config <path>
./dev eval --run <run-id>        # evaluation
./dev serve                      # optional inference
./dev nb                         # start jupyter / vscode notebook server in the right env
./dev data-prep                  # one-shot data prep
./dev clean
./dev help
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

No canonical Sid ML repo right now; the conventions are derived from the Notes + uvenv design.

## Escalation

- Need reproducible builds with exact deps → move to `pyproject.toml` + `uv.lock` (Topology 01)
- Ship inference as a service → add an app project (Topology 02), import model from this one
