# SkyPilot — alternative ML orchestrator

[SkyPilot](https://skypilot.readthedocs.io/) is the open-source predecessor and contemporary of dstack. Mature, multi-cloud, k8s-friendly, simpler config in some cases.

## When SkyPilot fits

- Heavy k8s use — SkyPilot has first-class k8s as a backend cloud
- Team already standardised on it
- Want the simpler `sky launch` semantics over dstack's declarative `apply`
- Need features dstack doesn't have (e.g. some specific cloud integrations)

## Comparison with dstack

| Axis | dstack | SkyPilot |
|---|---|---|
| Config format | `*.dstack.yml` declarative | `*.yaml` with `sky launch` |
| Cloud support | Wide — AWS/GCP/Azure/Lambda/RunPod/Vast/k8s + on-prem fleets | Wide — AWS/GCP/Azure/k8s + several niche |
| Fleets / pre-provisioned pools | First-class | Possible but less central |
| Gateways (TLS endpoints) | First-class | Manual setup |
| Volumes | First-class | Cloud-native (S3/PVC) |
| Dev environments (interactive) | First-class | `sky launch --idle-minutes-to-autostop` |
| Skill bundled in this marketplace | ✅ (the `dstack` plugin) | ❌ (use upstream docs) |

This plugin defaults to **dstack** because it's already wired into the marketplace. SkyPilot is fully supported as an alternative — if the user picks it, structure the repo similarly and use `sky/` instead of `.dstack/`.

## Repo layout for SkyPilot

```
my-ml/
├── sky/
│   ├── train.yaml
│   ├── eval.yaml
│   ├── serve.yaml
│   └── dev.yaml
├── apps/<project>/
├── notebooks/
├── configs/
├── scripts/
│   └── cloud/
│       ├── train-spot.sh        # sky launch -c train sky/train.yaml --detach-run
│       ├── eval.sh
│       └── serve.sh
└── README.md
```

## Example `sky/train.yaml`

```yaml
name: train-model

resources:
  accelerators: A100:1
  use_spot: true
  disk_size: 200

file_mounts:
  /workdir: .
  /checkpoints:
    source: s3://my-bucket/checkpoints   # persisted across spot preemption

envs:
  HF_TOKEN: null                 # null = passthrough from local env
  WANDB_API_KEY: null

setup: |
  pip install -r /workdir/requirements.txt

run: |
  cd /workdir
  python -m my_project.train \
    --config configs/baseline.yaml \
    --checkpoint-dir /checkpoints
```

## Example `scripts/cloud/train-spot.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

run_name="${1:-train-$(date +%Y%m%d-%H%M%S)}"

sky launch -c "$run_name" sky/train.yaml --detach-run -y
echo "Submitted as $run_name"
echo "Logs: sky logs $run_name"
echo "Stop: sky stop $run_name; sky down $run_name"
```

`-c <name>` is the cluster name (SkyPilot's term for a single VM or cluster). `--detach-run` submits without attaching.

## Spot + checkpointing with SkyPilot

SkyPilot's `--retry-until-up` and managed-jobs (`sky jobs launch`) handle spot recovery similar to dstack. Pair with cloud-bucket-mounted checkpoint dirs as above.

```bash
sky jobs launch -y --retry-until-up sky/train.yaml
```

`sky jobs` is the managed-spot mode — survives controller restarts, retries automatically. Equivalent to dstack's auto-restart for spot tasks.

## Anti-patterns

- Mixing dstack and SkyPilot configs in one repo — pick one
- Cloud-specific configs (`aws.yaml`, `gcp.yaml`) — SkyPilot picks the cheapest cloud unless you constrain
- Not using `file_mounts: /checkpoints: s3://...` for spot training — preemption = lost work
- `use_spot: true` without `--retry-until-up` — first preemption ends the run
