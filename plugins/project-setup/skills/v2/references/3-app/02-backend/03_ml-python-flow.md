# ML Python flow — `requirements.txt` + uvenv global env

The Python dependency flow for ML projects (Layout 04). Deliberately different from the app flow (`pyproject` + `uv sync`, owned by `references/3-app/02-backend/00_app-skeleton.md`). This file owns the ML variant — broad `requirements.txt`, one shared named global env via uvenv, the `uvenv-name` handshake with `ctl` — and the app-vs-ML comparison below.

## Why this is different

| App | ML |
|---|---|
| Deps are pinned exactly via `uv.lock` | Deps are broad version ranges (`torch>=2.4`, not `torch==2.4.1`) |
| Per-project `.venv` | One env shared across many experiment repos |
| `uv sync` recreates env from lockfile | `pip install -r requirements.txt` resolves freely |
| Reproducible deployment is critical | Ergonomic notebook flow + GPU lib stability matter more |
| Each project is independent | Experiments share heavy libs (torch, transformers, accelerate) |

ML envs accumulate. You install torch once for one recommender experiment, then reuse it for a classifier, a fine-tune, etc. Each project pip-installs a few extra libs into the shared env.

## uvenv — named global Python envs

`uvenv` is a thin shell wrapper around mise (Python versions) + uv (venvs + packages) that provides conda-style `activate <name>` ergonomics — named global envs you can activate from any directory.

```bash
# create a named global env
uvenv create --python=3.13 -n ml-recommender

# activate it
uvenv activate ml-recommender

# install
uvenv install -r requirements.txt
uvenv install torch transformers accelerate datasets

# list (global envs + local venvs + mise pythons)
uvenv list

# inside an experiment repo
cd <experiment-repo>/
uvenv activate "$(cat uvenv-name)"      # reads the env name from the file
ctl train --config configs/baseline.yaml
```

## `requirements.txt` shape

Human-authored, broad version ranges, comments:

```txt
# ML core
torch>=2.4
torchvision>=0.19
torchaudio>=2.4
transformers>=4.44
accelerate>=0.34
datasets>=3.0
peft>=0.12

# Training infra
wandb>=0.18
tensorboard>=2.17
hydra-core>=1.3
omegaconf>=2.3

# Data
pandas>=2.2
polars>=1.6
numpy>=2.0

# Dev
jupyter>=1.0
ipykernel>=6.29
black>=24.8
ruff>=0.6
```

No exact pins. Resolver picks compatible versions. If something breaks, pin the specific lib temporarily and document why.

## The `uvenv-name` file

Repo root contains a plain text file naming the env to activate:

```bash
$ cat uvenv-name
ml-recommender
```

`ctl` activates this env at the start of every subcommand:

```bash
# inside ctl
env_name=$(cat uvenv-name 2>/dev/null || echo "")
if [[ -z "$env_name" ]]; then
  die "no uvenv-name file — create one with: echo 'ml-<project>' > uvenv-name"
fi
uvenv activate "$env_name"
```

## Layout under Layout 04

```
<ml-repo>/
├── uvenv-name                       # contains "ml-<project>"
├── requirements.txt                 # broad ranges
├── .mise.toml                       # just python version
├── apps/<project>/src/<package>/    # importable package — wrappers, utilities
├── notebooks/                       # exploratory
├── configs/                         # per-experiment hyperparameters
├── scripts/
│   ├── train.sh
│   ├── eval.sh
│   └── data-prep.sh
├── data/                            # gitignored
├── models/                          # gitignored
├── outputs/                         # gitignored
└── README.md
```

No docker compose. No frontend. No `pyproject.toml` typically (but optional if you want to install `apps/<project>/` as a package into the env). Full ML repo shape: `references/2-repo/01-layouts/04_ml-project.md`.

## When to graduate to the app flow

- Need exact reproducibility (e.g. you're shipping a model server) → migrate inference to a separate app project (Layout 02) with `pyproject.toml` + `uv.lock` (`references/3-app/02-backend/00_app-skeleton.md`).
- Multiple devs need identical envs → consider `uv pip compile requirements.txt -o requirements.lock` as a middle ground.
- Experiment matrix grows past ~10 active configs → keep `requirements.txt` but versioned per-major-rev.

## Anti-patterns

- Mixing `pyproject.toml` + `uv.lock` and `requirements.txt` in one ML repo — pick one.
- Per-experiment venvs with duplicated torch installs — uvenv is the answer to this.
- Hard-pinning torch in `requirements.txt` — CUDA version mismatches everywhere.
- Notebook deps living in `requirements.txt` alongside training deps — separate `requirements-nb.txt` if it matters.
- Forgetting `uvenv-name` and the wrapper fails silently — fail loudly.

## See also

- `references/3-app/02-backend/00_app-skeleton.md` — the app flow this is deliberately different from
- `references/2-repo/01-layouts/04_ml-project.md` — the full ML repo shape
- `references/2-repo/07-ml-orchestration/00_custom-orchestrator.md` — cloud GPU runs via `scripts/cloud/` wrappers (spot + checkpoints, remote dev)
