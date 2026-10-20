# Composition. Configures logging, opens the pool and redis in lifespan, mounts every domain router under
# settings.server.prefix, registers the global error handler. Adds /health (alive) and /ready (deps). No rules here.
# With AUTH_ENABLED=FALSE it logs one warning at startup: a request with no credential acts as the
# reserved user.
