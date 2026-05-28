# ML Python flow — `requirements.txt` + uvenv global env

For ML projects (Layout 04). Different from app projects on purpose — see `pyproject-uv-sync-for-apps.md` for the comparison.

## Why this is different

| App | ML |
|---|---|
| Deps are pinned exactly via `uv.lock` | Deps are broad version ranges (`torch>=2.4`, not `torch==2.4.1`) |
| Per-project `.venv` | One env shared across many experiment repos |
| `uv sync` recreates env from lockfile | `pip install -r requirements.txt` resolves freely |
| Reproducible deployment is critical | Ergonomic notebook flow + GPU lib stability matter more |
| Each project is independent | Experiments share heavy libs (torch, transformers, accelerate) |

ML envs accumulate. You install torch once for `ml-recommender`, then reuse it for `ml-classifier`, `ml-fine-tune`, etc. Each project pip-installs a few extra libs into the shared env.

## uvenv — named global Python envs

[`uvenv`](https://github.com/sidhanthapoddar99/uvenv) (~/projects/02_OpenSource/02_dev_tools/uvenv) is a thin shell wrapper around mise (Python versions) + uv (venvs + packages). Provides conda-style `activate ml` ergonomics.

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
cd ~/projects/my-recommender
uvenv activate $(cat uvenv-name)        # reads the env name from the file
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
my-ml/
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

No docker compose. No frontend. No `pyproject.toml` typically (but optional if you want to install `apps/<project>/` as a package into the env).

## When to graduate to the app flow

- Need exact reproducibility (e.g. you're shipping a model server) → migrate inference to a separate app project (Layout 02) with `pyproject.toml` + `uv.lock`
- Multiple devs need identical envs → consider `uv pip compile requirements.txt -o requirements.lock` as a middle ground
- Experiment matrix grows past ~10 active configs → keep `requirements.txt` but versioned per-major-rev

## Anti-patterns

- Mixing `pyproject.toml` + `uv.lock` and `requirements.txt` in one ML repo — pick one
- Per-experiment venvs with duplicated torch installs — uvenv is the answer to this
- Hard-pinning torch in `requirements.txt` — CUDA version mismatches everywhere
- Notebook deps living in `requirements.txt` alongside training deps — separate `requirements-nb.txt` if it matters
- Forgetting `uvenv-name` and the wrapper fails silently — fail loudly
