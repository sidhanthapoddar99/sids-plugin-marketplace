# CLAUDE.md

This is the guidance file for the `shipboard` service. Please read all of it carefully before doing anything.

## Overview

The backend is FastAPI under `api/` and the frontend is Vite + React under `web/`. We used to have a Flask app under `server/` but that was removed in March; some older docs still reference it, ignore them. The database is Postgres. Migrations are Alembic.

## Rules

- ALWAYS run `make check` before committing. (Note: this used to be `make lint && make test`, the Makefile was consolidated in 0.3.)
- NEVER commit directly to main.
- You MUST NOT edit anything under `web/src/generated/`.
- Use type hints everywhere.
- Prefer small functions.
- Keep PRs focused.
- Don't add dependencies.
- Tests should be written for new code.
- IMPORTANT: Always use the repository pattern for database access.
- Environment variables are loaded from `.env`; NEVER hardcode secrets.

## Commit messages

Use the conventional commits form: `type(scope): summary`.
Types: feat, fix, docs, refactor, test, chore.
Scope is the top-level folder name: api, web, infra.
Summary is imperative, lower case, no full stop, under 72 characters.
Body explains why, not what. Wrap at 72.
Footer carries `Closes #NNN` when the commit closes an issue.
Never commit generated files under `dist/`.
Sign off with `-s`.
Squash fixup commits before opening the PR.
If you touch both api and web, use scope `all`.
Breaking changes get a `!` after the type.
Reference the ticket in the body if there is one.

## Frontend

The frontend uses React 18 with hooks. State management is Zustand. Styling is Tailwind. Components live in `web/src/components/` and pages in `web/src/pages/`. The API client is generated from the OpenAPI spec into `web/src/generated/` by `make client`. Routing is React Router v6. Forms use react-hook-form. Icons are lucide-react. Testing is Vitest with Testing Library. The dev server proxies `/api` to the backend on port 8000.

## Backend

FastAPI with SQLAlchemy 2.0 and Alembic. Routers live in `api/routers/`, one file per resource. Services in `api/services/`. Repositories in `api/repositories/`. Pydantic schemas in `api/schemas/`. Settings via pydantic-settings in `api/settings.py`. The app factory is `api/main.py`. Tests in `api/tests/` mirror the source tree. Use `pytest -x` for fast feedback. Coverage must stay above 80% (previously 70%).

## When in doubt

Ask.
