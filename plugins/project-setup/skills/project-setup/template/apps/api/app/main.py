# FastAPI app factory. Imports `settings` from app.config. Mounts routers under settings.server.prefix.
# Adds: /health (unauthenticated), rate limit middleware (settings.limits), no CORS middleware —
# the browser talks to its own origin, nginx or the vite proxy routes.
