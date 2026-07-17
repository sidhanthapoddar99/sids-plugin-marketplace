# Remote dev — SSH + VS Code Remote + Claude on the box

Interactive exploration on a GPU box you don't own. The setup: one command spins up a remote dev environment, you SSH in (or VS Code Remote attaches), and Claude Code can run inside the remote to operate on the codebase.

## dstack — `type: dev-environment`

```yaml
# tasks/dev.dstack.yml
type: dev-environment
name: my-ml-dev

python: "3.13"
ide: vscode                # adds the right wiring

env:
  - HF_TOKEN
  - WANDB_API_KEY

resources:
  gpu:
    name: A10, L4
    count: 1
    memory: 16GB..

# Auto-stop idle dev environments to save cost
inactivity_duration: 1h

volumes:
  - name: ml-dev-workspace
    path: /workspace

commands:
  - pip install -r requirements.txt

# Optional — install Claude Code on the remote
setup:
  - curl -fsSL https://claude.ai/install.sh | bash
```

```bash
dstack apply -f tasks/dev.dstack.yml -y
```

dstack:

- Provisions a GPU instance
- Configures SSH access (writes to `~/.ssh/config`)
- Surfaces a VS Code Remote attach URL
- Mounts the persistent volume at `/workspace`
- Auto-stops the box after `inactivity_duration` of no activity

## SSH from terminal

After `dstack apply` finishes, dstack writes a host entry like:

```
# ~/.ssh/config (managed by dstack)
Host my-ml-dev
  HostName <remote-ip>
  User ubuntu
  IdentityFile ~/.dstack/ssh/...
```

So `ssh my-ml-dev` Just Works.

## VS Code Remote

VS Code Remote-SSH extension picks up the host entry automatically. From command palette → "Remote-SSH: Connect to Host" → pick `my-ml-dev` → it attaches, opens the workspace, runs your dev environment inside the remote.

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

The `setup:` block in the dstack config installs Claude Code on the box. SSH in, run `claude` interactively.

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

**Default**: option B for cost (no GPU cost while idle); option A when the agent itself needs heavy file ops or GPU-direct work.

## remote-dev wrapper script

```bash
#!/usr/bin/env bash
# scripts/cloud/remote-dev.sh — spin up a remote dev env and surface the URL.
set -euo pipefail

dstack apply -f tasks/dev.dstack.yml -y

# After it's running, dstack writes the ssh config entry and prints:
#   - ssh my-ml-dev
#   - VS Code URL
# The script prints those, plus a one-liner reminder:

cat <<EOF

Remote dev ready.

  SSH:        ssh my-ml-dev
  VS Code:    open the URL above (or "Remote-SSH: Connect to Host: my-ml-dev")
  Stop:       dstack stop my-ml-dev -y

Cost reminder: auto-stops after 1h idle. Stop manually when done.

EOF
```

## What lives in the repo for remote dev to work

```
my-ml/
├── tasks/dev.dstack.yml           # dstack config
├── .vscode/
│   ├── settings.json              # remote interpreter path, etc.
│   └── extensions.json            # recommend pylance, ruff, etc.
├── scripts/cloud/
│   ├── remote-dev.sh              # the one-command bring-up
│   └── teardown.sh                # safety net
└── .gitignore                     # exclude .dstack/local-state if any
```

## SkyPilot equivalent

```bash
sky launch -c my-ml-dev --gpus A10:1 --idle-minutes-to-autostop 60 sky/dev.yaml
sky ssh my-ml-dev
```

SkyPilot doesn't have first-class VS Code integration like dstack's `ide: vscode`, but VS Code Remote-SSH works once you have `sky ssh` config writable.

## Anti-patterns

- Leaving idle dev environments running — cost accumulates fast; configure `inactivity_duration` / `--idle-minutes-to-autostop`
- Putting secrets in `.dstack.yml` — env passthrough, never literals
- Treating remote dev as a long-term workstation — short-lived, ephemeral, recreate as needed
- Forgetting to persist `/workspace` — losing work when the instance gets stopped
- Installing Claude on every remote when option B suffices
