# CI/CD — placeholder, GitHub Actions notes

CI/CD setup is intentionally out of scope for the initial bootstrap. Document the expected shape here so the skill can recommend it consistently when the project graduates.

## Open source — GitHub Actions

When the project is open source, default to GitHub Actions. Two workflows:

### `.github/workflows/check.yml` — on every PR

```yaml
name: check

on:
  pull_request:
  push:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_USER: ci
          POSTGRES_PASSWORD: ci
          POSTGRES_DB: ci
        ports: ["5432:5432"]
        options: --health-cmd pg_isready --health-interval 5s --health-timeout 3s --health-retries 5
      redis:
        image: redis:7-alpine
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: mise install
      - run: cd apps/backend && uv sync
      - run: cd apps/backend && uv run alembic upgrade head
        env:
          DATABASE_URL: postgresql+asyncpg://ci:ci@localhost:5432/ci
      - run: cd apps/backend && uv run pytest
      - run: cd apps/frontend && bun install
      - run: cd apps/frontend && bun check
      - run: cd apps/frontend && bun test
      - run: cd apps/frontend && bun run build
```

### `.github/workflows/release.yml` — on tag

```yaml
name: release

on:
  push:
    tags: ["v*"]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push backend
        uses: docker/build-push-action@v5
        with:
          context: ./apps/backend
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/backend:${{ github.ref_name }}
            ghcr.io/${{ github.repository }}/backend:latest
      - name: Build and push frontend
        uses: docker/build-push-action@v5
        with:
          context: ./apps/frontend
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/frontend:${{ github.ref_name }}
            ghcr.io/${{ github.repository }}/frontend:latest
```

## Self-hosted runner

For private projects with a self-hosted runner, same workflow but `runs-on: self-hosted` and mise pre-installed on the runner.

## Secrets

CI/prod secret placement (GitHub Actions secrets, self-hosted `.env.ci`, the Vault future state) is owned by `references/2-repo/03-env-config/03_secrets-matrix.md` — the only CI-local rule: ephemeral test-service creds (`ci/ci` above) may be hardcoded in the workflow.

## When `/ps-setup` runs

For an open-source project, offer to drop the `check.yml` workflow. For a private project, ask whether GitHub Actions or self-hosted, and drop the appropriate template.

For now, the bootstrapper just creates `.github/workflows/` with a `.gitkeep` and prints a hint to read `references/2-repo/05-ctl-scripts-tooling/06_ci-cd-future.md` for templates.

## Anti-patterns

- Hand-rolling CI YAML for every project — use a templated workflow
- Mixing test execution between CI and `ctl` — same commands; CI is just an environment
- Pushing images on every commit — only on tags or main
- Running migrations in CI workflow steps that aren't isolated — services should run, migrations apply, tests run, all in one job
- No status checks required on the default branch — set up GitHub branch protection
