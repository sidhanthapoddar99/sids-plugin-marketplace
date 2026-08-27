# Remote dev — SSH + VS Code Remote + Claude on the box

Interactive exploration on a GPU box you don't own. The setup: one command provisions a remote dev environment, you SSH in (or VS Code Remote attaches), and Claude Code can run inside the remote to operate on the codebase.

## The provisioning contract

`scripts/cloud/remote-dev.sh` (a thin wrapper over the provider CLI — `references/2-repo/07-ml-orchestration/00_custom-orchestrator.md`) must do all of this in one command:

1. **Provision a GPU instance** (spot or on-demand per flag; sane default GPU type + a max-price guard)
2. **Attach a persistent workspace** at `/workspace` — a re-attachable volume, or an object-store sync on start/stop
3. **Run setup** — `pip install -r requirements.txt`, plus optional Claude Code install (below)
4. **Write a stable `~/.ssh/config` host entry** so `ssh <alias>` Just Works, and rewrite it on every bring-up (IPs are ephemeral)
5. **Print the alias, the VS Code hint, and the stop command**
6. **Enforce idle auto-stop** — a cron/systemd idle-check on the box that shuts it down after ~1h of no sessions. Idle GPU boxes are the #1 cost leak; this is not optional.

## SSH from terminal

The host entry the script writes:

```
# ~/.ssh/config (managed by scripts/cloud/remote-dev.sh)
Host my-ml-dev
  HostName <remote-ip>
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519
```

So `ssh my-ml-dev` Just Works.

## VS Code Remote

VS Code's Remote-SSH extension picks up the host entry automatically. Command palette → "Remote-SSH: Connect to Host" → pick `my-ml-dev` → it attaches and opens `/workspace`.

Set in `.vscode/settings.json` (committed):

```json
{
  "python.defaultInterpreterPath": "/workspace/.venv/bin/python",
  "remote.SSH.connectTimeout": 60,
  "remote.SSH.useLocalServer": false
}
```

## Claude Code on the remote

Two options:

### Option A — Claude Code installed on the remote

The provisioning script's setup step installs Claude Code on the box. SSH in, run `claude` interactively.

```bash
ssh my-ml-dev
cd /workspace
claude
```

Claude runs on the remote, sees the remote filesystem, has access to the GPUs.

### Option B — Local Claude with remote workspace (via VS Code Remote)

You run Claude Code locally inside VS Code (with the project-setup plugin loaded), but VS Code's "current workspace" is the remote. Claude sees remote files via the VS Code Remote bridge.

Trade-offs:

| Aspect | A (remote claude) | B (local claude, remote workspace) |
|---|---|---|
| Where Claude runs | On the GPU box | On your laptop |
| Cost of idle claude session | GPU instance cost | Free (laptop is on anyway) |
| Latency to file ops | Native (fast) | VS Code bridge (slower) |
| GPU access from agent | Direct | Via SSH commands the agent invokes |
| MCP servers / plugins | Must install on remote | Local install works |

**Default**: option B for cost (no GPU cost while idle); option A when the agent itself needs heavy file ops or GPU-direct work. Agent-side mechanics: `references/2-repo/07-ml-orchestration/04_agent-ssh-access.md`.

## remote-dev wrapper script

```bash
#!/usr/bin/env bash
# scripts/cloud/remote-dev.sh — one-command remote dev env.
set -euo pipefail

# 1. provision (provider CLI), 2. attach /workspace, 3. run setup,
# 4. rewrite the ~/.ssh/config entry — then:

cat <<EOF

Remote dev ready.

  SSH:        ssh my-ml-dev
  VS Code:    "Remote-SSH: Connect to Host: my-ml-dev"
  Stop:       ./scripts/cloud/teardown.sh my-ml-dev

Cost reminder: auto-stops after 1h idle. Stop manually when done.

EOF
```

## What lives in the repo for remote dev to work

```
my-ml/
├── scripts/cloud/
│   ├── remote-dev.sh              # the one-command bring-up
│   └── teardown.sh                # safety net
├── .vscode/
│   ├── settings.json              # remote interpreter path, etc.
│   └── extensions.json            # recommend pylance, ruff, etc.
└── .gitignore
```

## Anti-patterns

- Leaving idle dev environments running — cost accumulates fast; the idle auto-stop belongs in the provisioning contract, not in memory
- Secrets as literals in provisioning scripts — env passthrough, never literals
- Treating remote dev as a long-term workstation — short-lived, ephemeral, recreate as needed
- Forgetting to persist `/workspace` — losing work when the instance gets stopped
- Hand-editing the `~/.ssh/config` entry — the script owns it and rewrites it per bring-up
- Installing Claude on every remote when option B suffices
