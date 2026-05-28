# Agent SSH access — how an agent operates on a remote box

When Claude (or another agent) is asked to run training, debug a remote job, or operate on the GPU box on the user's behalf, the agent needs predictable SSH access with the right guardrails.

## Two modes

### Mode 1 — agent on local, runs SSH commands

The agent has shell access locally. It runs `ssh my-ml-dev "..."` to do work on the remote.

- ✅ Works with any agent that has Bash access
- ✅ No agent install on the remote
- ❌ Each command is a fresh SSH session — slow for many small ops
- ❌ Long-running commands need detach (`nohup`, `screen`, `tmux`)

### Mode 2 — agent on remote, full session

Claude Code installed on the remote, opened in an SSH session. The agent's cwd is the remote workspace.

- ✅ Native file ops, fast
- ✅ Direct GPU access (`nvidia-smi`, `torch.cuda.is_available()`)
- ✅ Long-running commands trivial
- ❌ Costs GPU time while the agent is idle
- ❌ Needs Claude install + plugin sync to the remote

**Default**: Mode 1 unless the work is heavy enough to warrant Mode 2.

## Mode 1 setup

`~/.ssh/config` entry (written by dstack or by hand):

```
Host my-ml-dev
  HostName 1.2.3.4
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking no       # ONLY if the host is ephemeral and re-keyed often
  UserKnownHostsFile /dev/null   # same
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

`ControlMaster` lets the agent reuse an open connection for many commands — eliminates SSH handshake overhead.

The agent runs:

```bash
ssh my-ml-dev "cd /workspace && python -m my_project.eval --config configs/baseline.yaml"
```

Or `rsync`s files first, then runs.

## What the agent should know

A `CLAUDE.md` next to the repo root should describe:

- The remote host alias (`my-ml-dev`)
- Where the workspace lives on the remote (`/workspace`)
- The remote's GPU(s) — type, count, memory
- Activation commands (`source /workspace/.venv/bin/activate` or `uvenv activate ml-foo`)
- Long-running command convention (`nohup ... > /workspace/outputs/run.log 2>&1 &`)
- How to check job status (`tail -f /workspace/outputs/run.log`, `nvidia-smi`)
- The teardown command if the agent needs to stop the box (`dstack stop my-ml-dev -y`)

Sample CLAUDE.md addition:

```markdown
## Remote dev

This project runs heavy work on a remote GPU box. The host is `my-ml-dev`
(declared in `~/.ssh/config`, provisioned via `tasks/dev.dstack.yml`).

When you need to run training / eval / inference:

1. Spin up if not running: `ctl cloud up`
2. Check status: `dstack ps my-ml-dev` or `ssh my-ml-dev 'nvidia-smi'`
3. Submit a job: `ssh my-ml-dev 'cd /workspace && nohup python -m my_project.train --config configs/baseline.yaml > outputs/run.log 2>&1 &'`
4. Tail logs: `ssh my-ml-dev 'tail -f /workspace/outputs/run.log'`
5. Stop when done: `dstack stop my-ml-dev -y`

Cost: ~$N/hr while running. Auto-stops after 1h idle.

Do not run training synchronously over SSH — use the nohup-detach pattern
so the agent can return.
```

## Permission boundary

The agent should only have permissions you'd give a junior teammate:

- Read/write to the workspace — yes
- Submit jobs via dstack — yes
- Stop / start the box — **ask first** (cost implication)
- `rm -rf /workspace` — never (have the teardown script handle clean state)
- Modify `~/.ssh/authorized_keys` on the remote — never

Encode in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(ssh my-ml-dev:*)",
      "Bash(rsync:*)",
      "Bash(dstack apply:*)",
      "Bash(dstack ps:*)",
      "Bash(dstack logs:*)"
    ],
    "ask": [
      "Bash(dstack stop:*)",
      "Bash(dstack down:*)"
    ]
  }
}
```

## Mode 2 setup (agent on remote)

Install Claude Code in the dstack `setup:`:

```yaml
# tasks/dev.dstack.yml
setup:
  - curl -fsSL https://claude.ai/install.sh | bash
  - echo 'export PATH="$HOME/.claude/bin:$PATH"' >> ~/.bashrc
```

Sync plugins and `.claude/` settings:

```bash
# scripts/cloud/sync-claude.sh
rsync -a ~/.claude/settings.json my-ml-dev:.claude/settings.json
rsync -a ~/.claude/plugins/cache/ my-ml-dev:.claude/plugins/cache/
```

Then `ssh my-ml-dev` and run `claude` interactively. The agent sees the remote workspace as cwd, has Bash access to the box, has access to your plugins (synced).

## Detection — is the agent local or remote?

In CLAUDE.md, the agent should be able to tell:

```bash
# detect remote
[ "$(hostname)" = "my-ml-dev" ] && echo "remote" || echo "local"
```

The agent's behaviour might differ — on the remote, prefer native file ops; on local, prefer `ssh ... "..."`.

## Anti-patterns

- Hardcoded IP in `~/.ssh/config` for an ephemeral dstack box — let dstack manage the entry
- Skipping `ControlMaster` — every command pays the handshake
- Giving the agent `Bash(dstack down:*)` without "ask" — surprise teardowns
- Running training synchronously over SSH from the agent — agent blocks; long-running commands need `nohup`
- Forgetting to sync plugins to the remote in Mode 2 — agent loses capabilities
