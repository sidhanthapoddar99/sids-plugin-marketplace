# Cloud orchestration — `scripts/cloud/` wrappers, escalating to a thin CLI

Owns **how cloud GPU work is launched and managed**: no third-party orchestrator layer. Provisioning, spot runs, teardown, and status live in-repo as thin wrappers over the cloud provider's own CLI, escalating to a small custom binary only when the wrappers outgrow bash.

## Stage 1 — `scripts/cloud/` wrappers (default)

Most repos never leave this stage. A flat set of shell wrappers over the provider CLI (`aws` / `gcloud` / `az`) plus `ssh`/`rsync`:

```
scripts/cloud/
├── remote-dev.sh          # one-command GPU dev box (see 03_remote-dev-ssh-vscode.md)
├── train-spot.sh          # submit detached spot training (checkpoint contract applies)
├── sweep.sh               # submit a hyperparameter sweep
├── eval.sh                # submit an eval run
├── serve.sh               # optional inference service (see 02_inference-autoscaling.md)
├── status.sh              # query run/instance status (used by wait-for-run.sh and CI)
├── wait-for-run.sh        # poll status.sh until a run completes
└── teardown.sh            # safety net — stop every instance this repo started
```

Conventions:

- Each wrapper is **thin** — provider CLI calls + ssh, no business logic. The same thin-wrapper principle as `ctl` (`references/2-repo/05-ctl-scripts-tooling/00_script-overview.md`); `ctl cloud <verb>` may route to these.
- **State = instance tags** — tag every instance with the repo/run name so `status.sh` and `teardown.sh` can find them; no state file needed at this stage.
- **Detach by default** for long runs — submit, print the run name, return. `wait-for-run.sh` is the blocking primitive for CI and agents.
- Spot re-acquisition + checkpoint mounting live in the run wrappers; the contract is owned by `references/2-repo/07-ml-orchestration/01_spot-instances-and-checkpoints.md`.
- Secrets via env passthrough, never literals in the scripts.

## Stage 2 — a thin custom CLI (escalation)

Promote the wrappers to a small binary (Go / Rust / Python, Layout-05-style) **only when they accumulate cross-run state** — which runs are active, retry counts, checkpoint URIs, cost tracking — that tags and bash can no longer hold honestly.

```
my-ml/
├── cli/                              # the orchestrator
│   ├── main.go
│   ├── cmd/
│   └── internal/
│       ├── aws/                      # provider SDK calls
│       ├── ssh/                      # SSH session helpers
│       ├── state/                    # ~/.<tool>/state.json
│       └── checkpoints/
├── configs/<job>.yaml                # job specs the binary reads
└── …
```

State that survives runs:

```
~/.<tool>/state.json
{
  "active_runs": [
    {"id": "train-2026-05-20", "instance": "i-abc123", "spot": true, "checkpoint_uri": "s3://..."},
    {"id": "serve-prod", "instance": "i-def456", "spot": false}
  ]
}
```

Conventions for the binary: CLI command structure mirrors the wrapper verbs (`dev / train / sweep / eval / serve / status / teardown`); metrics + logs surface to the repo's `outputs/` dir plus a status file; the `scripts/cloud/` wrappers become one-line shims over it so CI and CLAUDE.md instructions don't change.

## What to ask the user during `/ps-setup`

1. **Cloud GPUs at all?** — no → skip this folder entirely; local/bare-metal only.
2. **Which provider(s)?** — determines the CLI the wrappers call.
3. **Spot policy** — spot for training/sweeps, on-demand for inference SLAs and final runs (`01_spot-instances-and-checkpoints.md`).
4. **Stage 2 wanted?** — only if the cross-run-state criterion above already holds; otherwise start at Stage 1 and escalate later.

## Anti-patterns

- Adopting a third-party orchestration platform for one repo's training runs — a dependency and a control plane you now operate, for what six shell scripts do.
- Fat wrappers — retry loops, cost logic, and state parsing in bash; that's the Stage 2 signal, not a reason for more bash.
- No `teardown.sh` — orphaned GPU instances are the most expensive bug in this file.
- Building Stage 2 on day one — the state.json schema is only knowable after the wrappers have run real workloads.
