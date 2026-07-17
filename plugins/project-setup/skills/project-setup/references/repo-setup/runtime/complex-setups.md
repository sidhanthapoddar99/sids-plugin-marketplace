# Complex setups — profiles, multi-mode compose trees + binary orchestrators

The standard runtime (one `docker/` with a profile-less `compose.yaml` + standalone configs + `compose.m.*` modifiers, driven by the `ctl` shell dispatcher) covers the vast majority of repos. This doc is for the escalations you reach when that's not enough:

0. **Profiles** — a genuine multi-group service mesh (several *independently-optional* service groups in arbitrary combinations) that standalone configs can't express legibly. → re-add a profiles axis. (The default model is profile-less; this is the rare opt-in.)
1. **Multi-mode compose** — you need structurally *different* stacks (single-node vs a multi-node cluster vs prod), not just overlays on one base. → `docker/<mode>/` directories.
2. **Binary orchestrator** — the shell `ctl` outgrows its job (structured state across runs, mode promotion). → a Go (or Rust/Python) CLI replaces the shell wrapper.

They travel together: the kind of project that needs `docker/<mode>/` (e.g. a blockchain test harness with 1/N/prod node topologies) is usually the kind that needs a binary to manage it. This is **Layout 05**.

> The simple runtime is documented in `runtime/docker-overview.md` (compose) and `runtime/script-overview.md` (ctl). This doc only covers the deltas for complex setups. Don't reach for any of it preemptively.

---

## Part 0 — profiles (the advanced service-selection axis)

The default model is **profile-less**: every service in the chosen compose file runs, and "a subset" is expressed as a standalone `compose.<name>.yaml` selected by name (`docker-overview.md`). At ≤5 services where you almost always want the whole set, a profile axis costs more than it pays — synthetic `all`/`none` entries, mutual-exclusion logic, config-aware recomputation — for a payoff that never materialises.

**Re-add profiles only when the project has several genuinely orthogonal, independently-optional service groups** mixed in arbitrary combinations — workers + observability + edge + debug tooling, toggled à la carte. That's a real shape, but uncommon, and even then a handful of standalone configs often expresses it more legibly. The test: can you *name* several independently-optional groups **and** confirm standalone configs can't express them? If not, stay profile-less.

To re-add the axis: tag services with `profiles:` in `compose.yaml`, restore `list_profiles()` in `_lib.sh` (grep `profiles:` from the base), and give `container/up.sh` a third selection axis (`--profile`, comma-list) feeding `--profile <p>` flags into the assembly. The interactive picker gains a profiles step *under* the chosen config. It's additive — the config + modifier axes are unchanged.

---

## Part 1 — multi-mode docker (`docker/<mode>/`)

When modes differ in *which and how many* services run (not just config), one profiled `compose.yaml` can't express it — a single-node stack and a 5-peer cluster are different topologies. Split by **mode directory**, each a self-contained mini-stack:

```
docker/
├── singlenode/
│   └── compose.yaml                 # one of each service
├── multinode/
│   ├── compose.yaml                 # base: N peers (scale via deploy.replicas / --scale)
│   ├── compose.m.no-ports.yaml      # modifier: strip host ports (behind a proxy)
│   ├── compose.m.traefik.yaml       # modifier: external Traefik edge
│   ├── compose.m.reset.yaml         # modifier: fresh-state (wipe volumes on up)
│   └── compose.m.test-temp.yaml     # modifier: ephemeral, tmpfs-backed test run
└── prod/
    └── compose.yaml                 # production topology (image tags, limits)
```

- **Each mode is a directory**, not a file. Its `compose.yaml` is that mode's base.
- **Within a mode, the same conventions hold**: `compose.m.<modifier>.yaml` for cross-cutting overlays, port-less base. The `.m.` marker means the same thing here as in the flat layout.
- **Multi-mode is itself the common reason to want profiles** (Part 0): a mode like `multinode` may genuinely have optional groups (`--profile obs` to add observability). If a mode needs them, re-add the axis *for that mode* per Part 0 — it's still the opt-in, not the baseline.
- Path discipline is unchanged (`../../apps`, `../../infra` — note the extra `..` because compose files are now one level deeper). See `runtime/docker-details.md`.

The binary (Part 2) picks the mode directory and assembles the `-f` list; the modes themselves are plain compose and **must remain runnable directly**:

```bash
# both must work:
cch multinode up
docker compose -f docker/multinode/compose.yaml -f docker/multinode/compose.m.no-ports.yaml up -d
```

---

## Part 2 — escalating `ctl` to a binary orchestrator

### When to escalate (and when NOT to)

Escalate the shell `ctl` to a real binary when **any** of these hold:

1. The `ctl` shell script grows past **~150 lines** of non-trivial logic (excluding comments/colour helpers).
2. **State persists between commands** — "is multinode running?", "which peer is leader?", "what port did I pick last time?".
3. **Multiple compose modes interact** — singlenode→multinode promotion, prod↔test-temp swaps.
4. **Operators, not just developers, use it** — the wrapper becomes the product surface.
5. **Branching on environment** gets deeply nested (`if mode==multi && reset && !no-ports …`).

The real trigger is **structured state across compose calls**; line count just correlates. If `ctl` only calls `docker compose -f … up` with light validation, **stay in shell** — don't add a binary preemptively.

### Language choice

| Language | When |
|---|---|
| **Go** (default) | Single static binary, `cobra`+`viper`, no runtime deps, easy cross-compile |
| **Rust** | Team already in Rust and wants it in the same build pipeline |
| **Python** | Team wants extensibility and accepts the runtime requirement (manage via uv/uvenv) |
| **TypeScript/Bun** | JS-heavy team; `bun build --compile` makes a single binary viable |

### Binary anatomy (Go)

```
my-chain/
├── docker/{singlenode,multinode,prod}/...   # the mode trees from Part 1
├── cchain/                          # the orchestrator
│   ├── main.go
│   ├── cmd/                         # cobra subcommands
│   │   ├── root.go                  #   cch
│   │   ├── singlenode.go            #   cch singlenode {up,down,logs,reset}
│   │   ├── multinode.go             #   cch multinode {up,down,scale N,reset,logs}
│   │   └── prod.go                  #   cch prod {up,down,upgrade}
│   ├── internal/
│   │   ├── compose/                 # compose call wrappers (assemble -f lists)
│   │   ├── state/                   # persisted state (~/.cch/state.json)
│   │   └── peer/                    # cluster-aware helpers
│   ├── go.mod
│   └── go.sum
└── cch                              # built binary at repo root (symlink/copy)
```

```go
// cchain/main.go
package main
import ( "github.com/spf13/cobra"; "my-chain/cchain/cmd" )
func main() { cmd.Execute() }

// cchain/cmd/root.go — cobra root with subcommands registered in init()
var rootCmd = &cobra.Command{ Use: "cch", Short: "my-chain orchestrator" }
```

### State management

The binary owns operational state across runs — never application data. Persist it predictably and version the schema:

- `~/.cch/state.json` — user-level state
- `./.cch-state` — project-local state (gitignored)

### Keep compose plain (the cardinal rule)

The binary is a **convenience over** `docker compose`, not a replacement. Keep dynamism (`${VAR}` substitution, volume paths) **in the compose files**; put state-management and UX **in the binary**. If essential behaviour hides inside Go, operators can't debug without reading Go. Both invocation styles must always work (see Part 1).

### README contract (4 paths, not 3)

A Layout 05 README documents **four** startup paths:

1. The binary — `cch multinode up` (preferred)
2. Raw compose — `docker compose -f docker/multinode/compose.yaml up -d`
3. Per-service host run (IDE debugging)
4. Building the binary — `cd cchain && go build -o ../cch`

(The standard three-path contract is in `runtime/overview.md`; complex setups add the build path.)

---

## Real-world reference

- The canonical Layout 05 shape: `docker/{singlenode,multinode,prod}/`, a Go orchestrator package, its binary at root. Cite a registered example from `references/integrations/examples-index.md` if one exists.

## Anti-patterns

- Writing the binary before the shell `ctl` actually outgrew its job — premature; the trigger is structured state, not aesthetics.
- Putting **business logic** in the orchestrator — it's compose plumbing, not the app.
- Hiding compose so deeply behind the binary that `docker compose -f …` no longer works — keep modes runnable directly.
- Reinventing what `docker compose` already does (health, deps, log multiplexing) — call it underneath.
- Conflating orchestrator state and service state — the orchestrator manages compose, never application data.
- Not documenting the binary's state file — operators need to know it exists and where.
- Using `docker/<mode>/` for a project that only needs overlays — that's the flat layout (`runtime/docker-overview.md`), not this.

## See also

- `runtime/overview.md` — how mise + ctl + docker + env interact (the simple case)
- `runtime/docker-overview.md` — the flat (single-mode) profile-less convention: standalone configs + `compose.m.*` modifiers
- `runtime/script-overview.md` — the shell `ctl` this escalates *from*
- `runtime/multi-stack.md` — the *across-repos* escalation: several stacks cooperating on one shared network (this page covers escalations within one repo)
- `layouts/05_infra-orchestrator.md` — the layout entry that points here
