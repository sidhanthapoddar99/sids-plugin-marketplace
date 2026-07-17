# ML orchestration — running training and inference on cloud GPUs

Layout 04 (`references/2-repo/layouts/04_ml-project.md`) defines the **repo shape** for an ML project. This subfolder covers the **operational shape** — how training, inference, and experiments actually run when you don't have a GPU under your desk.

## Three orchestrators in scope

| Tool | Status | Best at |
|---|---|---|
| **dstack** | ✅ already a sibling plugin in this marketplace | Spot-friendly GPU runs across clouds + Kubernetes + on-prem fleets, declarative `*.dstack.yml`, dev environments / tasks / services / fleets / volumes / gateways |
| **SkyPilot** | external — referenced, not bundled | Mature multi-cloud spot scheduling, fleet management, lighter declarative format |
| **Bespoke (future)** | placeholder | Niche use cases the above don't cover; pattern: thin orchestrator on top of cloud SDKs, similar to a Layout 05 Go CLI |

**Defer to dstack first** for new projects — the dstack plugin's skill already covers its CLI surface. This plugin's references *point* at the dstack skill, they don't duplicate it.

## Reference files

| File | Topic |
|---|---|
| `dstack.md` | When to reach for dstack + how to compose with the dstack plugin's skill |
| `skypilot.md` | When SkyPilot fits better; basic config shape |
| `custom-orchestrator.md` | Placeholder for a future bespoke orchestrator |
| `spot-instances-and-checkpoints.md` | Checkpoint-safe training patterns; surviving spot preemption |
| `inference-autoscaling.md` | Long-running inference with auto-redeploy on preemption + scale up/down |
| `remote-dev-ssh-vscode.md` | SSH into a remote box, VS Code Remote, Claude Code running inside the remote |
| `agent-ssh-access.md` | How an agent (Claude or otherwise) operates safely over SSH on a remote box |
| `cicd-for-ml.md` | CI/CD pipelines for ML: lint, smoke-train, eval, model registry |

## What kinds of jobs live here

| Job shape | Reference |
|---|---|
| **Short batch training** (one-shot, <2h) | `spot-instances-and-checkpoints.md` (the simple half) |
| **Long-running training with checkpoints** (resume across spot preemption) | `spot-instances-and-checkpoints.md` |
| **Hyperparameter sweep** (N parallel small runs) | `dstack.md` (`dstack apply` per config) or `skypilot.md` (`sky launch --gpus`) |
| **Batch inference** (queue + workers) | `inference-autoscaling.md` |
| **Online inference** (web endpoint, autoscale) | `inference-autoscaling.md` |
| **Eval pass** (run model against benchmark, write report) | `cicd-for-ml.md` |
| **Remote dev** (interactive exploration on a GPU box) | `remote-dev-ssh-vscode.md` |
| **Agent-driven remote work** (Claude running on the GPU box) | `agent-ssh-access.md` |

## Scripts that belong in the repo

For Layout 04 + cloud orchestration, expect (under `scripts/cloud/`):

```
scripts/cloud/
├── train-spot.sh             # dstack apply or sky launch — long training, checkpointed
├── train-batch.sh            # short training run, no spot
├── sweep.sh                  # hyperparameter sweep launcher
├── eval.sh                   # eval pass on benchmark
├── serve.sh                  # inference deploy (autoscaled, spot-friendly)
├── remote-dev.sh             # spin up an interactive remote box
└── teardown.sh               # destroy all active runs (cost safety)
```

Plus configs:

```
.dstack/profiles.yml          # if using dstack
.dstack.yml or <task>.dstack.yml per job
sky/<task>.yaml               # if using SkyPilot
```

## What the skill should ask

When `/ps-setup` is invoked for an ML project, after the standard Layout 04 questions, also ask:

1. **Cloud orchestration**: dstack / SkyPilot / both / neither / custom?
2. **Spot or on-demand**?
3. **Training cadence**: one-shot, sweep, continuous?
4. **Inference**: yes/no; if yes, batch or online; if online, autoscale?
5. **Remote dev**: does the user want a one-command "spin up a GPU box and SSH in" flow?
6. **Agent access to remote**: does an agent (Claude) need to run training/eval on the remote on the user's behalf?

If dstack is selected → also load the `dstack` skill's guidance (the dstack plugin's `SKILL.md`).
