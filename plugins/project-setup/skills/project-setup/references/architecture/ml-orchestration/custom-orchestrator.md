# Custom orchestrator — placeholder for Sid's own future tool

If dstack and SkyPilot don't cover a use case, the escape hatch is to build a thin custom orchestrator. Pattern is similar to chimere's Go CLI (Layout 05): a small binary that calls cloud SDKs / kubectl / SSH, with structured state across runs.

## When this is justified

Almost never. Reach for it only when:

- Both dstack and SkyPilot have a specific gap that can't be patched upstream
- The deployment surface is unusual enough that off-the-shelf tools add more friction than they remove
- You're building a product that includes orchestration as part of the offering (not just orchestration as a means to an end)

## What it might look like

Thin Go (or Rust, Python) binary at repo root:

```
my-ml/
├── cli/                              # the orchestrator
│   ├── main.go
│   ├── cmd/
│   └── internal/
│       ├── aws/                      # boto3-equivalent calls
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

## Don't write this on day one

For now, this file is a **placeholder**. If Sid actually starts building one, the conventions land here:

- Folder layout
- State file location and schema
- CLI command structure (cobra / clap / argparse)
- How it surfaces metrics + logs (probably to the same `outputs/` dir + a status file)
- How `project-setup` recognises a repo that uses it

Until then: use dstack. It's already here, it works, and customising the upstream is cheaper than rolling your own.

## What to ask the user during `/ps-setup`

If the user says "I want my own orchestrator":

1. **What gap does dstack/SkyPilot not fill for you?** — get a concrete answer
2. **Have you tried patching upstream?** — dstack accepts PRs
3. **Are you sure?** — building orchestrators is a full-time job
4. **OK, then** — describe the pattern (Go CLI similar to chimere), point at this file as a stub, and proceed

The skill should default to gently steering toward dstack first.
