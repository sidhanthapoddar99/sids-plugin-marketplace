# App packaging — how one app becomes an image

Owns how a **single** app packages itself into a container image: its Dockerfile conventions, image naming/tagging, the healthcheck endpoint contract, the build-arg-vs-runtime-env split, and its `.dockerignore`. Orchestration — compose, the reverse proxy, expose tiers, how images wire together — is L2, owned by `references/2-repo/04-docker/00_docker-overview.md`; this file stops at the boundary of one app's own image.

## Dockerfile-per-app conventions

Each app owns its `Dockerfile` (every-app contract, `references/3-app/01-structure-and-stack/00_app-anatomy.md`). Standard shape:

- **Multi-stage build** — a deps/build stage, a slim runtime stage that copies only the built artifact + resolved deps (the Python multi-stage-with-uv Dockerfile is in `references/3-app/02-backend/00_app-skeleton.md`; the frontend build→nginx Dockerfile in `references/2-repo/04-docker/04_proxy-and-exposure.md`).
- **Pinned base image** — `python:3.12-slim`, `oven/bun:1`, etc., pinned to a real tag, never `latest`. Versions are illustrative — check current stable and let the user pick.
- **Non-root user** — create and `USER` a non-root account in the runtime stage; a container running as root is an unnecessary blast radius.
- **Small final image** — slim/alpine base, no build toolchain in the runtime stage, no dev dependencies, `--no-cache` on package installs.

## Image naming and tagging

- Name by app: `<product>/<app>` (e.g. `acme/api`, `acme/web`).
- **Tag immutably** for deploys — a git SHA or a semver release tag, never redeploying a moving `latest`. `latest` is a convenience alias for local, not what prod pins.
- The prod config pins exact tags (`references/2-repo/03-env-config/03_secrets-matrix.md` § prod, `references/2-repo/04-docker/00_docker-overview.md`).

## Healthcheck endpoint contract

The app exposes a health endpoint (e.g. `/api/health`) that its serving layer implements and compose/orchestrator probes — a two-way contract:

- The app **implements** liveness/readiness (`references/3-app/10-deployment/00_serving.md`); readiness reflects real dependencies (DB reachable, migrations applied).
- Compose/orchestrator **probes** it (`HEALTHCHECK` / compose `healthcheck`, wired at L2 — `references/2-repo/04-docker/05_production-readiness.md`).

Keep the endpoint cheap and unauthenticated-but-internal so probes don't need credentials.

## Build args vs runtime env

Classify each value:

| Kind | Passed as | Example |
|---|---|---|
| **Build-time** — baked into the artifact at build | `ARG` (+ `--build-arg`) | a frontend's `VITE_API_BASE_URL`, a build channel |
| **Runtime** — read when the container starts | `ENV` / `env_file` | DB URL, secrets, worker counts |

Frontend public vars are build-time and bake into the bundle — the isolation rule (no secret among them) is owned by `references/2-repo/03-env-config/02_frontend-env-isolation.md`; the general precedence (build-time vs runtime, who wins) by `references/2-repo/03-env-config/00_env-precedence.md`. A runtime secret must never be a build arg — build args are visible in image history.

## `.dockerignore`

Each app ships a `.dockerignore` so its build context stays small and clean: exclude `.venv/` / `node_modules/`, `.git`, `data/`, `.env*`, tests/fixtures, and local caches. This shrinks context upload, speeds builds, and — critically — keeps `.env*` and local state out of the image.

## Anti-patterns

- **`latest` base tag** — non-reproducible builds; pin the base.
- **Running as root** in the runtime stage — add a non-root user.
- **Single-stage build shipping the toolchain** — bloated image, larger attack surface; multi-stage it.
- **A runtime secret as a build arg** — it's baked into image history; pass secrets at runtime.
- **No `.dockerignore`** — `.env`, `.git`, and `node_modules` leak into context (and maybe the image).
- **Redeploying a moving `latest` tag** to prod — pin an immutable SHA/semver.
- **Restating compose/proxy wiring here** — that's L2; this file is one app's own image.

## See also

- `references/3-app/10-deployment/00_serving.md` — the healthcheck + worker model this image runs
- `references/3-app/02-backend/00_app-skeleton.md` — the backend multi-stage Dockerfile
- `references/2-repo/04-docker/00_docker-overview.md` — compose orchestration + tag pinning (L2 owner)
- `references/2-repo/04-docker/05_production-readiness.md` — healthcheck probes, limits (L2)
- `references/2-repo/03-env-config/00_env-precedence.md` — build-time vs runtime precedence
- `references/2-repo/03-env-config/02_frontend-env-isolation.md` — frontend build-arg isolation
