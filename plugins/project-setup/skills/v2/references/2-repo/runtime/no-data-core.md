# No data core — the topology swap (`DATA_SVCS=()`)

The shipped template is **data-core-shaped**: it assumes a `postgres + redis` core, and several workers + the base compose default to it. A large, common class of projects has **no database** — static frontends, pure API gateways, stateless microservices, published SDKs, ML repos, tooling repos. This doc is the topology analogue of `script-alternatives.md` (which covers *tool* swaps): what to change to express "I have no data layer."

**The single switch is `DATA_SVCS`.** Set it empty in `_lib.sh` and every worker degrades gracefully — but a few files still carry data-core assumptions you edit once. Like `script-alternatives.md`, this is about editing the *generated project's* copy, not the shipped snippet.

## The inversion: apps become the always-on core

With a data core, the data layer is the always-on base and `ctl dev` brings it up for the host apps. With **no** data core, **the apps themselves are the whole base** — backend + frontend + nginx all run in `compose.yaml`, and there's nothing for `ctl dev` to bring up in containers (it just runs the host processes). This is the single biggest adaptation, and it's mostly automatic once `DATA_SVCS` is empty.

## The lines to change

| File | Change |
|---|---|
| **`_lib.sh`** | `read -r -a DATA_SVCS <<< "${DATA_SVCS:-}"` — **empty default** (was `postgres redis`). Everything below keys off this. |
| **`_lib.sh`** | If the project has no required secrets, soften the guards (the `[ADAPT]` one-liners are inline): `require_env` → load-if-present-never-die; `check_env_schema` → warn-don't-fail. A defaulted `.env` shouldn't force a `ctl setup` that does nothing. |
| **`dev/host.sh`** | Already guarded — with `DATA_SVCS` empty it skips the `dc … up -d` + `wait_healthy` and just runs the host apps. `require_tools mise docker` → drop `docker` if dev needs no containers. |
| **`config/setup.sh`** | Already guarded — skips `mkdir data/...` when `DATA_SVCS` is empty. |
| **`config/status.sh`** | Already guarded — prints "data core: none". Repoint the `containers` health check at your app services (e.g. `health_table backend frontend nginx`). |
| **`container/health.sh`** | Already falls back to `dc config --services` (all compose services) when `DATA_SVCS` is empty. |
| **`compose.yaml`** | Remove the `postgres`/`redis` services and the apps' `depends_on: {postgres: service_healthy, …}`. The apps are now the base. |

## Compose + expose, app-only

- **Base** is the app stack (backend + frontend + nginx), all always-on. Add **app-service healthchecks** so `ctl health` is meaningful — use a tool already in each image:
  - python image: `["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\""]`
  - node image: `["CMD-SHELL", "node -e \"fetch('http://localhost:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]`
  - alpine/nginx: `["CMD-SHELL", "wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1"]`
- **Expose tiers shift to the apps.** With no data layer, `expose_data` is moot; `expose` stays nginx-only (the safe default — the reverse proxy is the sole entry point), `expose_all` publishes backend + frontend + nginx for direct debugging. Drop `expose_data`; `ctl dev` no longer needs it.
- **`ctl dev`** brings up nothing in containers — it just runs the host processes (and the Vite proxy handles `/api`).

## Worked example

A FastAPI + Next.js toolkit with no DB runs the profile-less, no-data-core path end to end: `DATA_SVCS=()`, apps as the base, `expose`=nginx / `expose_all`=all three, a `compose.backend.yaml` standalone slice, soft env guards, and `migrate`/`test`/`lint` dropped (no DB, no test flow *yet* — re-add them when earned). It's the reference instantiation of this doc.

## See also

- `script-alternatives.md` — the *tool* swaps (no mise / docker / uv→uvenv / bun); this doc is its *topology* sibling
- `docker-overview.md` — the standalone-config / `.m.` modifier model the base plugs into
- `script-overview.md` — the `ctl`/`scripts` model; `DATA_SVCS` is the data-core switch
