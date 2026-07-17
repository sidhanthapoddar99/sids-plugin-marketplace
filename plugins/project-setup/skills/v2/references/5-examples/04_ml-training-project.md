# Example 04 — ML training project (Layout 04)

A complete, anonymized ML training/experiment repo: a shared **uvenv** global Python env, `requirements.txt` (not `uv.lock`), first-class notebooks, per-experiment `configs/`, gitignored data/model/output dirs, and the cloud-orchestration additions (`scripts/cloud/` wrappers, persistent checkpoint storage). Domain here is a generic text-classification model — read the *shape*, not the task.

This is a worked instance of `references/2-repo/layouts/04_ml-project.md`. Every rule it demonstrates is owned elsewhere; the "Which references govern each part" table at the end maps each piece to its owner. Nothing here is normative.

## Annotated tree

```
ml-textcat/                            # ONE training/experiment repo, its own git repo
├── .env                               # HF_TOKEN, WANDB_API_KEY, cloud creds — gitignored
├── .env.example                       # same keys, no values
├── .mise.toml                         # python 3.13 ONLY — no node, no other toolchains
├── requirements.txt                   # human-authored, BROAD ranges (torch>=2.4), commented — not uv.lock
├── uvenv-name                         # one line: "ml-textcat" — the shared global env ctl activates
├── ctl                                # task dispatcher; activates the uvenv from uvenv-name, then runs
├── apps/                              # code in a package folder, never loose in root
│   └── textcat/
│       ├── src/textcat/               # importable package — ML wrappers ARE a lib, so src-layout is fine here
│       │   ├── __init__.py
│       │   ├── data.py                # dataset loading / preprocessing
│       │   ├── model.py               # model definition
│       │   ├── train.py               # `ctl train` entrypoint — reads a config, writes checkpoints
│       │   └── eval.py                # `ctl eval` entrypoint
│       └── tests/                     # unit tests for data/model utilities
├── notebooks/                         # first-class, exploratory — numbered by stage
│   ├── 01_data-exploration.ipynb
│   ├── 02_baseline.ipynb
│   └── 03_error-analysis.ipynb
├── configs/                           # per-EXPERIMENT hyperparameters — one YAML per run, NO single config.yaml
│   ├── baseline.yaml
│   ├── ablation-lr.yaml
│   └── ablation-aug.yaml
├── scripts/                           # local (bare-metal GPU) entrypoints
│   ├── train.sh                       # local training
│   ├── eval.sh
│   ├── data-prep.sh                   # one-shot data prep
│   └── cloud/                         # remote-GPU wrappers — thin over the provider CLI
│       ├── remote-dev.sh              # bring up an interactive GPU dev box
│       ├── train-spot.sh              # submit detached spot training
│       ├── sweep.sh                   # submit a hyperparameter sweep
│       ├── eval.sh
│       ├── serve.sh                   # optional inference service
│       ├── status.sh                  # query run/instance status
│       ├── teardown.sh                # safety net — stop every run
│       └── wait-for-run.sh
├── data/                              # gitignored (large) — only .gitkeep + README live in git
│   ├── raw/.gitkeep
│   ├── processed/.gitkeep
│   └── README.md                      # where the real data lives + how to fetch it
├── models/                            # gitignored — LOCAL checkpoints; remote runs write to persistent cloud storage
│   └── .gitkeep
├── outputs/                           # gitignored — logs, plots, eval reports, W&B run dirs
│   └── .gitkeep
├── docs/                              # optional
├── .claude/                           # empty initially
├── CLAUDE.md                          # summarizes the ML conventions + links references
└── README.md                          # the three-path root README
```

## What makes this an ML repo (shape-defining choices)

| Choice | Why it differs from an app repo |
|---|---|
| `requirements.txt`, broad ranges | Shared global env across many experiment repos — a per-repo lockfile would force N copies of torch. Owner: `references/3-app/backend/ml-python-flow.md`. |
| `src/textcat/` package (src-layout) | Unlike a run-service app (flat `app/`), ML wrappers are importable → src-layout is correct here. Owner: `references/3-app/backend/app-skeleton.md`. |
| `configs/<experiment>.yaml`, no `config.yaml` | One YAML per run is the experiment axis; there is no single service config. |
| `data/ models/ outputs/` gitignored | Large/derived artifacts never enter git — `.gitkeep` + a data README stand in. |
| No `docker/`, no `infra/`, no frontend | ML runs on bare metal / cloud GPUs; a UI or inference server is a **separate** app project. |

## `ctl` subcommands

`ctl` activates the uvenv named in `uvenv-name` before every subcommand (mechanics owned by `references/3-app/backend/ml-python-flow.md`):

```
ctl train --config configs/baseline.yaml   # python -m textcat.train --config …
ctl eval  --run <run-id>                    # evaluation
ctl sweep --config configs/ablation-lr.yaml # local or → scripts/cloud/sweep.sh
ctl nb                                       # jupyter/notebook server in the right env
ctl data-prep                                # one-shot data prep
ctl clean / ctl help
```

## Checkpoints and spot survival

Local runs checkpoint into `models/` (gitignored). Remote spot training does **not** rely on the box surviving: `scripts/cloud/train-spot.sh` attaches persistent storage at `/checkpoints`, and `train.py` writes there. When the wrapper re-acquires an instance after a preemption, the storage re-attaches and training resumes from the latest checkpoint — so the ephemeral instance's disk is disposable. The storage/retry contract is owned by `references/2-repo/ml-orchestration/spot-instances-and-checkpoints.md`; the wrapper bodies by `references/2-repo/ml-orchestration/custom-orchestrator.md`.

## Graduation

If this repo needs to *ship* an inference service (exact reproducibility, a running server), that server is a **separate app project** — Layout 02 with `pyproject.toml` + `uv.lock` — importing model artifacts from here. Criteria owned by `references/3-app/backend/ml-python-flow.md`.

## Which references govern each part

| Part of the tree | Owner reference |
|---|---|
| Overall repo shape, `scripts/cloud/` additions | `references/2-repo/layouts/04_ml-project.md` |
| `requirements.txt`, `uvenv-name`, uvenv flow, graduation | `references/3-app/backend/ml-python-flow.md` |
| `apps/textcat/src/` package layout (src-vs-flat) | `references/3-app/backend/app-skeleton.md` |
| `.mise.toml` python-only runtime | `references/2-repo/runtime/mise.md` |
| `ctl` dispatcher model | `references/2-repo/runtime/script-overview.md` |
| `.env` / `.env.example` keys, secrets | `references/2-repo/env-and-config/env-precedence.md`, `references/2-repo/env-and-config/secrets-matrix.md` |
| `scripts/cloud/` wrapper bodies + conventions | `references/2-repo/ml-orchestration/custom-orchestrator.md` |
| Checkpoint storage / spot retry contract | `references/2-repo/ml-orchestration/spot-instances-and-checkpoints.md` |
| Interactive remote dev box (`remote-dev.sh`) | `references/2-repo/ml-orchestration/remote-dev-ssh-vscode.md` |
| `serve.sh` inference service | `references/2-repo/ml-orchestration/inference-autoscaling.md` |
| `.claude/` empty + `CLAUDE.md` guidance | `references/handoffs/claude-folder.md` |
| Root `README.md` three-path contract | `references/2-repo/readme-three-paths.md` |

## See also

- `references/2-repo/layouts/04_ml-project.md` — the layout this example instantiates
- `references/5-examples/00_index.md` — example ↔ layout ↔ variant map
- `references/5-examples/02_canonical-1be-1fe.md` — the app-repo contrast (pyproject + uv.lock, docker triad)
