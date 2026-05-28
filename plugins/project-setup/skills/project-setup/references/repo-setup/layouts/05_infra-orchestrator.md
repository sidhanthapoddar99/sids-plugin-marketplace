# Layout 05 — infra orchestrator

A docker compose tree driven by a Go (or Rust/Python) CLI binary. Example: `chimere-chain-2025` (blockchain multinode testing — 1 singlenode, N multinode, prod).

> This is the layout entry. For the **escalation triggers** (when a `ctl` shell wrapper should become a binary), the binary anatomy, state management, and the multi-node `docker/<mode>/` tree, see `references/repo-setup/runtime/complex-setups.md`.

## When it fits

- Multi-mode compose setups beyond `dev`/`prod` (e.g. singlenode / multinode / prod)
- Need structured state across compose runs (which nodes are up, which port to use, which seed to bootstrap)
- Shell wrappers grow past ~150 lines or get too branchy
- Operator-facing CLI is the primary interface (not just dev convenience)

## Tree

```
my-chain/
├── apps/
│   └── <services>/                 # the actual services (Layout 01–02 internally)
├── docker/
│   ├── singlenode/
│   │   └── compose.yaml
│   ├── multinode/
│   │   ├── compose.yaml            # base
│   │   ├── compose.no-ports.yaml   # overlay
│   │   ├── compose.reset.yaml      # overlay — fresh-state mode
│   │   ├── compose.test-temp.yaml  # overlay — ephemeral testing
│   │   └── compose.traefik.yaml    # overlay
│   └── prod/
│       └── compose.yaml
├── cchain/                         # the Go orchestrator
│   ├── main.go
│   ├── cmd/                        # cobra subcommands
│   ├── internal/
│   ├── go.mod
│   └── go.sum
├── cch                             # built binary at repo root (symlinked or copied)
├── scripts/                        # legacy shell scripts kept as reference
├── docs/                           # documentation-template
├── .claude/
└── README.md / CLAUDE.md
```

Key differences from Layout 02:

- `docker/<mode>/` instead of `docker/<file>` — modes are folders containing per-mode compose + overlays
- Go binary at the orchestration layer
- No `ctl` shell dispatcher — the binary replaces it

## When NOT to use Go

- Shell dispatcher is < 150 lines and not branchy → just use Layout 02's `ctl`
- The orchestrator just calls `docker compose` with flags → shell is fine
- Team doesn't know Go and never will → use Rust or Python; the language matters less than the structured-state requirement

The escalation trigger is **structured state across compose calls**, not line count alone. Lines just correlate.

## Binary anatomy

```go
// cchain/main.go
package main

import (
    "github.com/spf13/cobra"
    "my-chain/cchain/cmd"
)

func main() {
    cmd.Execute()
}

// cchain/cmd/root.go — cobra root with subcommands:
//   cch singlenode {up,down,logs,reset}
//   cch multinode {up,down,scale N,reset,logs}
//   cch prod {up,down,upgrade}
//   cch status
```

The binary owns the state (node count, ports, peer addresses) and calls `docker compose` underneath.

## Real-world reference

- `chimere-chain-2025` — `~/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025` — the canonical example. See `cchain/main.go`, `cchain/cmd/`, and the `docker/` tree.

## Common mistakes

- Reaching for Go before the shell wrapper actually outgrew its job
- Using the binary as a shell-script-replacement when shell would do
- Hiding compose files behind the binary so deeply that the operator can't run `docker compose ...` directly — keep the compose files plain, the binary is a convenience
- Conflating orchestrator-state and service-state — the orchestrator only manages compose, not application data

## README contract for Layout 05

In addition to the standard three startup paths, the README must explain **both** the binary (`./cch multinode up`) AND the underlying compose calls (`docker compose -f docker/multinode/compose.yaml up`). The binary should be the convenience; the compose calls remain the ground truth.
