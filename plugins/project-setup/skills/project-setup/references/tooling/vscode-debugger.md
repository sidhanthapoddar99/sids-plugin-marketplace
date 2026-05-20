# VS Code debugger setup

Optional but useful. The "no-docker host run" startup path (`scripts/three-startup-paths.md`) becomes much more attractive when the IDE debugger attaches cleanly. This reference outlines the `.vscode/` files that make that work.

## Files

```
.vscode/
├── launch.json          # debug configurations
├── settings.json        # workspace settings (interpreter, formatter, ...)
├── extensions.json      # recommended extensions for contributors
└── tasks.json           # optional — wrap `./dev` subcommands
```

All committed. Per-user overrides go in `.vscode/settings.local.json` (gitignored).

## `launch.json` — Topology 02 / 03

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Backend (Python, uvicorn)",
      "type": "debugpy",
      "request": "launch",
      "module": "uvicorn",
      "args": [
        "app.main:app",
        "--reload",
        "--host", "0.0.0.0",
        "--port", "8000"
      ],
      "cwd": "${workspaceFolder}/apps/backend",
      "envFile": "${workspaceFolder}/.env",
      "justMyCode": false,
      "console": "integratedTerminal"
    },
    {
      "name": "Backend (Rust)",
      "type": "lldb",
      "request": "launch",
      "program": "${workspaceFolder}/apps/backend-rust/target/debug/api",
      "cwd": "${workspaceFolder}/apps/backend-rust",
      "envFile": "${workspaceFolder}/.env",
      "preLaunchTask": "cargo build"
    },
    {
      "name": "Frontend (Vite, Chrome)",
      "type": "chrome",
      "request": "launch",
      "url": "http://localhost:5173",
      "webRoot": "${workspaceFolder}/apps/frontend/src",
      "sourceMaps": true
    },
    {
      "name": "Run tests (Python, pytest)",
      "type": "debugpy",
      "request": "launch",
      "module": "pytest",
      "args": ["-vv"],
      "cwd": "${workspaceFolder}/apps/backend",
      "envFile": "${workspaceFolder}/.env",
      "justMyCode": false
    }
  ],
  "compounds": [
    {
      "name": "Full stack (backend + frontend)",
      "configurations": ["Backend (Python, uvicorn)", "Frontend (Vite, Chrome)"]
    }
  ]
}
```

## `settings.json`

```jsonc
{
  "python.defaultInterpreterPath": "${workspaceFolder}/apps/backend/.venv/bin/python",
  "python.testing.pytestEnabled": true,
  "python.testing.pytestArgs": ["apps/backend/tests"],

  "rust-analyzer.linkedProjects": ["${workspaceFolder}/apps/backend-rust/Cargo.toml"],

  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.formatOnSave": true
  },
  "[typescript]": {
    "editor.defaultFormatter": "biomejs.biome",
    "editor.formatOnSave": true
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "biomejs.biome",
    "editor.formatOnSave": true
  },
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true
  },

  "files.exclude": {
    "**/node_modules": true,
    "**/.venv": true,
    "**/target": true,
    "**/__pycache__": true,
    "**/dist": true,
    "**/.vite": true
  }
}
```

## `extensions.json`

```jsonc
{
  "recommendations": [
    "ms-python.python",
    "ms-python.debugpy",
    "charliermarsh.ruff",
    "rust-lang.rust-analyzer",
    "vadimcn.vscode-lldb",
    "biomejs.biome",
    "bradlc.vscode-tailwindcss",
    "ms-vscode-remote.remote-ssh"
  ]
}
```

When a contributor opens the workspace, VS Code prompts to install these.

## `tasks.json` — wrap `./dev` subcommands

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "cargo build",
      "type": "shell",
      "command": "cargo build",
      "options": { "cwd": "${workspaceFolder}/apps/backend-rust" }
    },
    {
      "label": "./dev migrate up",
      "type": "shell",
      "command": "./dev migrate up",
      "presentation": { "reveal": "always", "panel": "shared" }
    },
    {
      "label": "./dev test",
      "type": "shell",
      "command": "./dev test"
    }
  ]
}
```

Then `Ctrl+Shift+P → Tasks: Run Task` surfaces them.

## When to skip

- Headless server projects without interactive debugging needs — VS Code itself optional
- Team standardised on a different editor (JetBrains, neovim) — provide equivalent configs there
- Pure ML projects where notebooks are the IDE — use `jupyter` extension + `ipykernel`

## Real-world reference

None of Sid's example repos currently ship full `.vscode/` configs — the snippet here is the recommendation, not an extant pattern.

## Anti-patterns

- Per-user paths committed (`/Users/sid/...`) — break for everyone else
- Skipping `envFile` — debugger doesn't see `.env` values
- `justMyCode: true` for everything — sometimes you need to step into a dep
- VS Code-only conventions where the project should still work without — keep `./dev` as the canonical entrypoint
