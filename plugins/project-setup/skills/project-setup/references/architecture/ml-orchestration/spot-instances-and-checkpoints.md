# Spot instances + checkpoint-safe training

Spot/preemptible GPU instances are 3–5× cheaper than on-demand. They get reclaimed with little notice. Surviving preemption is a property of the **training script**, not the orchestrator.

## The rule

**Any spot-eligible training run must be checkpoint-resumable.** Without that, your first preemption is your last 4 hours of GPU time wasted.

## Three requirements

1. **Persistent checkpoint storage** outside the spot instance (S3, GCS, Azure Blob, or a cloud volume that survives instance termination)
2. **Periodic checkpointing** — save every N steps or M minutes, not just at the end
3. **Resume-from-latest** on startup — the training script must detect existing checkpoints and resume

## Where checkpoints live

| Backend | Mount pattern |
|---|---|
| dstack | `volumes: [{ name: ckpts, path: /checkpoints }]` — declared in `*.dstack.yml` |
| SkyPilot | `file_mounts: { /checkpoints: s3://bucket/job-name }` |
| Custom | Mount S3 via s3fs / rclone, or use `aws s3 sync` in setup |

The path inside the container is the same; the orchestrator handles the persistence.

## Training script — resume pattern

```python
# apps/<project>/src/train.py
import os
from pathlib import Path

CHECKPOINT_DIR = Path(os.environ.get("CHECKPOINT_DIR", "/checkpoints"))
CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

def latest_checkpoint() -> Path | None:
    ckpts = sorted(CHECKPOINT_DIR.glob("ckpt_*.pt"), key=lambda p: p.stat().st_mtime)
    return ckpts[-1] if ckpts else None

def save_checkpoint(state, step):
    path = CHECKPOINT_DIR / f"ckpt_{step:08d}.pt"
    tmp = path.with_suffix(".pt.tmp")
    torch.save(state, tmp)
    tmp.rename(path)           # atomic — no half-written checkpoints

    # Keep the last K
    for old in sorted(CHECKPOINT_DIR.glob("ckpt_*.pt"))[:-3]:
        old.unlink()

def main():
    model, optimizer, start_step = build_or_resume(latest_checkpoint())
    for step in range(start_step, total_steps):
        train_step(model, optimizer)
        if step % 500 == 0:
            save_checkpoint({"model": model.state_dict(), "optim": optimizer.state_dict(), "step": step}, step)
```

Key bits:

- **Atomic write** — `tmp.rename(path)` so preemption never leaves a half-file
- **Step-numbered filenames** — clear ordering, easy to debug
- **Keep last K** — prevent unbounded growth
- **Resume detects most-recent file** — works after any preemption

## Checkpoint cadence

Trade-off: more frequent = more I/O but less work lost.

| Training duration | Cadence |
|---|---|
| Short (<2h) | Every 500 steps, or at the end |
| Medium (2–12h) | Every 1000 steps, or every 30 min |
| Long (>12h) | Every 30 min, plus end-of-epoch |

Tune via configs/<experiment>.yaml; don't hard-code in the training script.

## Spot retry policy

In dstack:

```yaml
type: task
name: train
spot_policy: auto         # tries spot first, falls back to on-demand
retry:
  on_events: [preemption]
  duration: 24h           # try to re-acquire for up to 24h
```

In SkyPilot managed jobs:

```bash
sky jobs launch -y --retry-until-up sky/train.yaml
```

The orchestrator handles re-acquiring an instance. The training script handles resuming from the checkpoint. **Both parts must work** — the orchestrator alone can't save you.

## Wandb / TensorBoard / metrics

Same rule applies to metric logging — write to a persistent location, not just the spot instance's local disk.

```python
import wandb
wandb.init(
    project="my-recommender",
    id=os.environ.get("WANDB_RUN_ID"),       # set to a stable value to resume the same run
    resume="allow",
    dir="/checkpoints/wandb",                # persistent
)
```

## Batch vs long-running

| Job type | Spot? | Checkpoint? |
|---|---|---|
| Quick sanity-check (5 min smoke test) | On-demand — preemption noise costs more than money saved | Optional |
| Hyperparameter sweep (N small runs) | Spot — restart cheap | Optional per-run, mandatory for runs >30min |
| Single long training | Spot + checkpoints + retry | **Mandatory** |
| Final paper-result training | On-demand to eliminate preemption variance | Optional |

## Anti-patterns

- Saving to `/tmp/checkpoint.pt` — gone on preemption
- Saving every 10 steps to S3 — I/O bottleneck (multi-GB per save)
- Resume-from-step-0 always — preemption resets your work
- Forgetting to flush metrics — last 30min of metrics lost
- Mounting S3 to the checkpoint dir but not testing that resume actually works — discover at preemption #1
