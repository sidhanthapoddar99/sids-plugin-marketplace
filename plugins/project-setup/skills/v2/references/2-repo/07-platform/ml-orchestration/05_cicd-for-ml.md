# CI/CD for ML projects

App CI/CD (`references/2-repo/tooling/ci-cd-future.md`) is about lint + test + build images. **ML CI/CD** has additional concerns: smoke-training, eval against benchmark, model registry / promotion, dataset versioning, and reproducibility.

## Pipeline tiers

| Tier | Trigger | Runs | Time budget |
|---|---|---|---|
| **Cheap** — every PR | lint + unit tests + small smoke-train | 5–10 min on CI runner (CPU) |
| **Medium** — on main / nightly | eval against held-out set + small benchmark | 30–60 min on GPU, submitted via `scripts/cloud/` |
| **Expensive** — on tag / release | full training + full eval + model promotion | hours–days; cloud-submitted — CI only orchestrates |

Don't try to run the expensive tier on every PR — it'll bankrupt you. Match cadence to value.

## Cheap tier — GitHub Actions

```yaml
# .github/workflows/cheap.yml
name: cheap
on:
  pull_request:
  push:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: mise install
      - run: pip install -r requirements.txt
      - run: ruff check . && ruff format --check .
      - run: pytest apps/<project>/tests/ -m "not gpu"
      - name: Smoke-train (CPU)
        run: |
          python -m my_project.train \
            --config configs/smoke.yaml \
            --max-steps 10 \
            --device cpu
```

`configs/smoke.yaml` is a tiny config used only for smoke tests — micro batch size, 10 steps, asserts loss decreases.

## Medium tier — eval pass, submit a cloud run

For nightly / merge-to-main:

```yaml
# .github/workflows/eval.yml
name: eval
on:
  schedule:
    - cron: "0 6 * * *"        # 06:00 UTC daily
  workflow_dispatch:

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Submit eval run
        env:
          CLOUD_CREDENTIALS: ${{ secrets.CLOUD_CREDENTIALS }}
        run: |
          ./scripts/cloud/ci-bootstrap.sh
          ./scripts/cloud/eval.sh --detach --name "eval-$(date +%Y%m%d)"
      - name: Wait + collect results
        run: |
          ./scripts/cloud/wait-for-run.sh "eval-$(date +%Y%m%d)"
          ssh eval-box 'cat /workspace/outputs/eval-results.txt' > eval-results.txt
      - name: Post results
        run: |
          # write to wandb / post to slack / open a PR with the metrics file
          ./scripts/cloud/post-eval-results.sh eval-results.txt
```

CI runner doesn't have a GPU. It submits the job, waits, collects results.

## Expensive tier — on tag

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags: ["v*"]

jobs:
  train-and-publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Submit full training
        run: |
          ./scripts/cloud/train-spot.sh --detach --name "${{ github.ref_name }}" --config configs/release.yaml
      - name: Wait for training
        run: ./scripts/cloud/wait-for-run.sh "${{ github.ref_name }}"
      - name: Push model artefacts
        run: |
          aws s3 cp /checkpoints/${{ github.ref_name }}/model.safetensors \
            s3://my-models/${{ github.ref_name }}/model.safetensors
      - name: Promote in registry
        run: |
          ./scripts/cloud/promote-model.sh ${{ github.ref_name }} production
```

## Pipeline scripts under `scripts/cloud/`

```
scripts/cloud/
├── wait-for-run.sh             # polls run status until completion
├── post-eval-results.sh        # post metrics to wandb/slack
├── promote-model.sh            # update model registry symlink/tag
├── teardown.sh                 # stop all active runs (cost safety)
└── ci-bootstrap.sh             # set up CI-side deps (provider CLI, jq, etc.)
```

### `wait-for-run.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
run="$1"
while true; do
  status=$(./scripts/cloud/status.sh "$run")   # provider CLI / custom orchestrator query
  case "$status" in
    "")                    sleep 10 ;;                            # not yet seen
    "running"|"submitted") sleep 30 ;;
    "done")                echo "✓ $run done"; exit 0 ;;
    "failed"|"aborted")    echo "✗ $run $status"; exit 1 ;;
    *)                     echo "?? $run $status"; sleep 30 ;;
  esac
done
```

## Reproducibility checklist

- Pin `.mise.toml` (Python version)
- Commit `requirements.txt` with broad ranges; lock with `uv pip compile` if exact pins matter
- Seed random / numpy / torch — same config → same numbers
- Log every hyperparameter to wandb / file
- Tag the data version (snapshot a known fixed dataset for benchmarks)
- Hash the config + data version into the run name

## Dataset versioning

For benchmarks: snapshot the dataset to S3/GCS with a version tag (`s3://my-data/bench-v3/`). Training/eval configs reference the version, not "latest". This way a year-old eval result is reproducible.

For training data: `dvc`, `lakefs`, or just `git lfs` + cloud bucket. Pick one; document in the repo.

## What the skill should produce

For an ML project, drop:

- `.github/workflows/cheap.yml` (always)
- `.github/workflows/eval.yml` (if cloud GPU runs are in use)
- `.github/workflows/release.yml` (if model is shipped)
- `configs/smoke.yaml` (for the CPU smoke test)
- `scripts/cloud/wait-for-run.sh`, `teardown.sh`, `promote-model.sh`

Don't drop everything; ask which tiers the project needs.

## Anti-patterns

- Full training in every PR — too expensive
- No CI at all — regressions land silently
- Untested smoke configs — break only at release time
- `latest` model promoted by default — pin versions, promote explicitly
- Running eval on the current main branch's code against a year-old model — drift; pin both
