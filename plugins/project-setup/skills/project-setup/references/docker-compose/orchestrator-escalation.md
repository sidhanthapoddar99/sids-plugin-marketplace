# When to escalate `ctl` to a real orchestrator binary

Most projects never need this. But for projects with complex compose graphs and structured state between commands, the shell wrapper grows past its useful size and a real binary helps.

## Triggers

Escalate when **any** of these are true:

1. **`ctl` shell script grows past ~150 lines** of non-trivial logic (not counting comments, color helpers, prefix wrappers)
2. **State persists between commands** — "is multinode running?", "which peer is leader?", "what port did I pick last time?"
3. **Multiple compose modes interact** (singlenode → multinode promotion, prod → test-temp swaps)
4. **Operators need it**, not just developers — the wrapper becomes the product surface
5. **Branching on environment** gets nested: `if mode == multi && reset && !no-ports then ...`

## Trigger NOT met → stay with shell

If the wrapper just calls `docker compose -f ... up` with light input validation, shell is fine. Don't add complexity preemptively.

## Language choice

| Language | When |
|---|---|
| **Go** | Single-binary distribution, cobra for subcommands, no runtime deps. Default. |
| **Rust** | If team already uses Rust and wants the binary in the same build pipeline |
| **Python** | If team wants extensibility and accepts the runtime requirement (uv/uvenv to manage) |
| **TypeScript/Bun** | If team is JS-heavy; single-binary via `bun build --compile` is now viable |

Go is the most common pick because:

- Compiles to a single static binary
- `cobra` + `viper` are battle-tested for CLI + config
- Type-safe state management
- Easy cross-compile

## Layout (Topology 08 pattern)

```
my-chain/
├── docker/
│   ├── singlenode/compose.yaml
│   ├── multinode/{compose.yaml,compose.no-ports.yaml,...}
│   └── prod/compose.yaml
├── cchain/                          # the Go orchestrator
│   ├── main.go
│   ├── cmd/                         # cobra subcommands
│   │   ├── root.go
│   │   ├── singlenode.go
│   │   ├── multinode.go
│   │   └── prod.go
│   ├── internal/
│   │   ├── compose/                 # compose call wrappers
│   │   ├── state/                   # persisted state (e.g. ~/.cch/state.json)
│   │   └── peer/                    # cluster-aware helpers
│   ├── go.mod
│   └── go.sum
└── cch                              # built binary at repo root (symlink or copy)
```

## Binary anatomy

```go
// cchain/main.go
package main

import (
    "github.com/spf13/cobra"
    "my-chain/cchain/cmd"
)

func main() { cmd.Execute() }

// cchain/cmd/root.go
var rootCmd = &cobra.Command{
    Use:   "cch",
    Short: "my-chain orchestrator",
}

func init() {
    rootCmd.AddCommand(singlenodeCmd, multinodeCmd, prodCmd, statusCmd)
}

func Execute() {
    if err := rootCmd.Execute(); err != nil {
        os.Exit(1)
    }
}
```

## State management

The orchestrator owns state across runs. Persist somewhere predictable:

- `~/.cch/state.json` for user-level state
- `./.cch-state` in the repo for project-local state (gitignored)

Schema versioned. State is **operational metadata** — never application data.

## Keep compose plain

The binary is a convenience. The compose files **stay readable and runnable directly**:

```bash
# Both must work:
./cch multinode up
docker compose -f docker/multinode/compose.yaml up -d
```

If the binary hides essential behaviour (env munging, dynamic volume paths) inside Go code, the operator can't debug without reading Go. Keep dynamism in the compose files (via `${VAR}` substitution) and put state-management + UX in the binary.

## README contract

When a project has Topology 08, the README must document **four** startup paths, not three:

1. The binary (`./cch multinode up`) — preferred
2. Raw docker compose (`docker compose -f docker/multinode/compose.yaml up`)
3. Per-service host run (for IDE debugging)
4. Building the binary (`cd cchain && go build -o ../cch`)

## Real-world reference

- `chimere-chain-2025` — the canonical example. See `cchain/main.go`, `cchain/cmd/`, README's docker section.

## Anti-patterns

- Writing the binary before the shell wrapper outgrows its job — premature
- Putting business logic in the orchestrator — it's compose plumbing
- Hiding the compose files behind the binary so deeply that `docker compose` doesn't work
- Reinventing what `docker compose` already does — use it underneath, don't replace
- Not documenting the binary's state file — operators need to know it exists
