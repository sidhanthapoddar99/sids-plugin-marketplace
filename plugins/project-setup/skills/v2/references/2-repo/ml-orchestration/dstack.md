# dstack — the default ML orchestrator

dstack is already a plugin in this marketplace. **Use the `dstack` skill directly** for the CLI surface, config schema, and operational flow — don't duplicate it here.

This file says **when** to reach for dstack and **how** to compose it with a `project-setup`-shaped repo.

## Cite the dstack skill

When `/ps-setup` decides dstack is in play, it should:

1. Confirm the dstack plugin is installed (`/plugin list` shows `dstack@sids-plugin-marketplace`)
2. Open the dstack skill's `SKILL.md` for the actual `dstack apply` / `dstack ps` / `*.dstack.yml` mechanics
3. Use this file only for **how dstack fits inside a project-setup-shaped repo**

## When dstack fits

- Spot-friendly GPU jobs (training, sweeps, batch inference)
- Cross-cloud — same config runs on AWS, GCP, Azure, Lambda Labs, RunPod, Vast, on-prem
- Dev environments (interactive remote GPU box)
- Long-running services with auto-restart on preemption
- Fleets (pre-provisioned pool of nodes to schedule against)
- Volumes (persistent storage across runs)
- Gateways (public endpoints with TLS)

## When dstack might NOT fit

- Single fixed cloud where you want to lean on that cloud's native primitives (SageMaker, Vertex AI)
- Tight integration with k8s-native workloads where SkyPilot's k8s mode or raw `kubectl` is preferred
- Org policy that disallows the dstack control plane

## Repo layout for dstack-driven ML

```
my-ml/
├── .dstack/
│   ├── profiles.yml              # backend selection (project, GPU types, max price)
│   └── ...
├── .dstack.yml                   # default task (e.g. interactive dev env)
├── tasks/                        # per-job dstack configs
│   ├── train.dstack.yml
│   ├── sweep.dstack.yml
│   ├── eval.dstack.yml
│   ├── serve.dstack.yml          # inference service
│   └── dev.dstack.yml            # interactive dev env
├── apps/<project>/
├── notebooks/
├── configs/
├── scripts/
│   └── cloud/
│       ├── train-spot.sh         # dstack apply -f tasks/train.dstack.yml -y -d
│       ├── eval.sh
│       ├── serve.sh
│       └── teardown.sh           # dstack stop --all -y
├── data/  models/  outputs/
└── README.md
```

## Example `tasks/train.dstack.yml`

```yaml
type: task
name: train-model

python: "3.13"

env:
  - HF_TOKEN
  - WANDB_API_KEY

# Resources — let dstack pick the cheapest matching offer
resources:
  gpu:
    name: A100, H100
    count: 1
    memory: 40GB..

# Spot is the default for cost; on-demand for time-critical
spot_policy: auto      # auto | spot | on-demand

# Where checkpoints live — survives preemption
volumes:
  - name: model-checkpoints
    path: /checkpoints

commands:
  - pip install -r requirements.txt
  - python -m my_project.train --config configs/baseline.yaml --checkpoint-dir /checkpoints
```

Resume on preemption: when dstack restarts the job (auto-retry), the volume is re-attached at `/checkpoints` and training resumes from the latest checkpoint. See `spot-instances-and-checkpoints.md`.

## Example `scripts/cloud/train-spot.sh`

```bash
#!/usr/bin/env bash
# Submit training as a detached spot job. Logs streamable via `dstack logs <run>`.
set -euo pipefail

run_name="${1:-train-$(date +%Y%m%d-%H%M%S)}"

dstack apply -f tasks/train.dstack.yml -y -d -n "$run_name"
echo "Submitted as $run_name. Watch: dstack logs $run_name"
echo "List:           dstack ps -v"
echo "Stop:           dstack stop $run_name -y"
```

## Composition with the dstack skill

For any concrete dstack operation (writing a `*.dstack.yml`, applying it, debugging a stuck run), defer to the `dstack` skill. This skill knows the CLI flags, the config schema, and the operational gotchas.

The `project-setup` skill's role is **structural** — where the files live, what the wrapper scripts call, how dstack fits into the repo. Pair the two.

## Anti-patterns

- Duplicating dstack's CLI documentation here — defer to its skill
- Hard-coding cloud creds in `*.dstack.yml` — use env vars (`HF_TOKEN`, `AWS_*`)
- Forgetting `volumes:` for checkpoints — spot preemption wipes the box
- Running interactive dev environments long-term as `task` instead of `dev-environment` — dev-env has SSH/VS Code wiring baked in
