# Layout 05 — infra orchestrator

Owns the **repo shape** for a docker-compose tree driven by a compiled CLI binary (Go, or Rust/Python/Bun) instead of the `ctl` shell dispatcher. Generic example shape: a blockchain-style multinode test harness with `singlenode` / `multinode` / `prod` topologies.

This file owns the **tree** only. The escalation machinery that lands you here — the multi-mode `docker/<mode>/` convention, the ctl→binary escalation triggers, binary anatomy, state management, and the 4-path README contract — is owned by `references/2-repo/runtime/complex-setups.md`. Don't restate it; link it.

## When it fits (routing signal)

Pick this layout when a repo needs **structured state across compose calls** — which nodes are up, which port was chosen, which peer is leader — and multiple *structurally different* compose modes (not just overlays). The authoritative escalation rule (5 conditions; structured-state is the real trigger, line count only correlates) is owned by `references/2-repo/runtime/complex-setups.md` § "When to escalate". If the shell `ctl` still fits, that's Layout 02, not 05.

## Tree

```
my-chain/                             # generic: a multinode test harness
├── apps/
│   └── <services>/                   # the actual services (Layout 01–02 shape internally)
├── docker/
│   ├── singlenode/
│   │   └── compose.yaml
│   ├── multinode/
│   │   ├── compose.yaml              # base topology
│   │   └── compose.m.<modifier>.yaml # per-mode overlays — convention owned by complex-setups.md
│   └── prod/
│       └── compose.yaml
├── cchain/                           # the CLI orchestrator package (anatomy → complex-setups.md)
│   ├── main.go
│   ├── cmd/                          # subcommands
│   ├── internal/                     # compose wrappers, state/, peer helpers
│   ├── go.mod
│   └── go.sum
├── cch                               # built binary at repo root (symlink/copy)
├── scripts/                          # legacy shell kept as reference, optional
├── docs/                             # → references/1-ecosystem/docs-placement.md
├── .claude/                          # → references/handoffs/claude-folder.md
└── README.md / CLAUDE.md
```

## What makes it Layout 05 (deltas vs Layout 02)

| Axis | Layout 02 | Layout 05 |
|---|---|---|
| `docker/` layout | flat files (`compose.yaml`, `compose.<name>.yaml`) | `docker/<mode>/` directories, one self-contained mini-stack per mode |
| Orchestration surface | `ctl` shell dispatcher | compiled binary at the orchestration layer |
| Cross-run state | none | binary owns operational state (node count, ports, peers) |

The binary is a **convenience over** `docker compose`, never a replacement — the compose files stay plain and directly runnable. Both `cch multinode up` and `docker compose -f docker/multinode/compose.yaml up -d` must always work. This rule and its rationale are owned by `references/2-repo/runtime/complex-setups.md` § "Keep compose plain".

## Audit checks

- Repo has `docker/<mode>/` directories (not flat compose files) → confirm each mode is *structurally* different, not just an overlay; if overlays would do, it's Layout 02.
- A binary exists but only calls `docker compose … up` with light validation → over-escalated; the shell `ctl` was enough.
- `docker compose -f …` no longer works because behaviour hides inside the binary → violates keep-compose-plain (owned by complex-setups.md).

## Anti-patterns

- Reaching for a binary before the shell `ctl` outgrew its job — the trigger is structured state, not aesthetics (owned by complex-setups.md § anti-patterns).
- Conflating orchestrator state (compose plumbing) with application/service data — the orchestrator never manages app data.
- Using `docker/<mode>/` for a project that only needs overlays on one base — that's the flat Layout 02 runtime.

## See also

- `references/2-repo/runtime/complex-setups.md` — the owner of the multi-mode tree, escalation triggers, binary anatomy, state management, and the 4-path README contract.
- `references/2-repo/layouts/02_multi-app-monorepo.md` — the layout this escalates *from*.
- `references/2-repo/runtime/docker-overview.md` — the flat profile-less compose convention the modes reuse.
- `references/handoffs/examples-registry.md` — cite a registered Layout 05 repo if one exists; otherwise propose the pattern on its own merits and flag the absence.
