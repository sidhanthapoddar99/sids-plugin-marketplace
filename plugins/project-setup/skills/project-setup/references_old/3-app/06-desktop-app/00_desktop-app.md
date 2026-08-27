# Desktop — Tauri (Rust) + Electron

Default desktop framework: **Tauri** (Rust shell, web-tech UI). Electron is the fallback when Tauri's Rust-side or webview limitations bite.

## When Tauri vs Electron

| | **Tauri** | **Electron** |
|---|---|---|
| Bundle size | Small (~5–15 MB) | Large (50–150 MB) |
| Memory | Lower (system webview) | Higher (bundled Chromium) |
| Webview | System (WebKit on macOS, WebView2 on Windows, WebKitGTK on Linux) | Bundled Chromium (consistent everywhere) |
| Native API | Rust (extend via commands) | JS/Node |
| Ecosystem maturity | Younger; growing fast | Mature, larger |
| Use when | You want small + native-feeling | You want guaranteed webview parity across OS |

**Default: Tauri.** Electron is fine when you specifically need bundled Chromium behaviour or a heavy Electron-only npm ecosystem dep.

## Tauri layout (under a monorepo)

```
my-app/
├── apps/
│   ├── backend/                    # shared API (optional — desktop can also be standalone)
│   ├── frontend/                   # web — optional
│   └── desktop/
│       ├── package.json            # frontend deps (Vite + React + shadcn — same stack as web)
│       ├── tauri.conf.json         # Tauri config
│       ├── vite.config.ts
│       ├── src/                    # frontend code (Vite)
│       │   ├── App.tsx
│       │   └── ...
│       └── src-tauri/              # Rust shell
│           ├── Cargo.toml
│           ├── tauri.conf.json
│           ├── icons/
│           └── src/
│               ├── main.rs
│               └── commands.rs     # Rust commands callable from JS
└── …
```

The frontend half of Tauri is the **same** stack as the web frontend (Layout 02). The Rust side is small — bootstraps the webview, handles native filesystem/menu/tray/IPC.

## Sharing UI between web + desktop

If the project has both web and desktop frontends with shared UI: that's Layout 02 (multi-frontend workspaces). `apps/web/` + `apps/desktop/` both depend on `packages/ui` + `packages/styles`. Same tokens, same components.

```
my-app/
├── apps/
│   ├── web/                # Vite SPA
│   └── desktop/            # Tauri shell + Vite frontend
├── packages/
│   ├── ui/
│   └── styles/
└── …
```

Tauri's `src/` directory imports from the shared packages just like `apps/web/`.

## Reusing web `packages/` from the shell

The desktop shell's web layer is an ordinary workspace consumer — it depends on the **same** `packages/` the web app does, never a forked copy:

- **`packages/ui`** — components render identically in the webview; no desktop-specific fork.
- **`packages/styles`** — one `tokens.css`, so light/dark and brand stay in lockstep across web and desktop (`references/3-app/05-package/01_tokens-setup.md`).
- **`packages/services`** — the typed API clients; the desktop app hits the same backend contract as web, so it imports the same client rather than re-implementing fetch calls.
- **`packages/types`** — shared entity/contract types.

The **only** desktop-specific code is the shell (`src-tauri/` Rust commands, or Electron `main.js`/`preload.js`) — native filesystem, tray, menu, IPC. That thin native layer belongs to this app; everything above it is shared through `packages/`, per the no-cross-app-imports rule (`references/3-app/01-structure-and-stack/00_app-anatomy.md`). A desktop-only wrapper around a shared component lives in the desktop app's `src/`; a component both surfaces want lives in `packages/ui`. Package internals: `references/3-app/05-package/00_shared-packages.md`.

## Electron layout (when chosen)

```
apps/desktop-electron/
├── package.json
├── main.js                 # Electron main process
├── preload.js              # contextBridge for IPC
├── renderer/               # Vite-built UI
│   ├── index.html
│   └── src/
├── electron-builder.json   # packaging config
└── resources/
```

Same multi-frontend sharing applies (`packages/ui`, `packages/styles`).

## Dev flow

```bash
# Tauri
cd apps/desktop
bun install
bun tauri dev            # builds Rust + starts Vite + opens window

# Electron
cd apps/desktop-electron
bun install
bun run electron:dev
```

`ctl` can wrap these:

```bash
ctl desktop             # bun tauri dev (from apps/desktop)
ctl desktop electron    # bun run electron:dev (from apps/desktop-electron)
```

## Distribution

- **Tauri**: `bun tauri build` produces `.dmg` / `.msi` / `.deb` / AppImage. Code signing per platform (Developer ID for macOS, EV cert for Windows).
- **Electron**: `electron-builder` does similar.

CI on tag pushes builds + signs + uploads to GitHub Releases.

## Anti-patterns

- Building a desktop app when an Electron-wrapped web view would suffice — but also: building a desktop wrapper for a tiny web app that should just be a web app
- Mixing Tauri and Electron in the same repo — pick one
- Not sharing tokens/components with the web frontend when both exist — duplication rots
- Putting all native logic in JS (Electron) or Rust (Tauri) when the other side fits better
- Skipping code signing — users get unsigned-app warnings forever

## See also

- `references/2-repo/01-layouts/02_multi-app-monorepo.md` — shared packages story
- `references/3-app/01-structure-and-stack/00_app-anatomy.md` — the every-app contract; sharing only via `packages/`
- `references/3-app/05-package/00_shared-packages.md` — package internals reused by the shell
- `references/3-app/05-package/01_tokens-setup.md` — `tokens.css` lives in `packages/styles` when shared
- `references/handoffs/examples-registry.md` — cite a registered desktop repo if one exists
