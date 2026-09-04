# Composition. Configures logging, opens the pool and redis in lifespan, mounts every domain router under
# settings.server.prefix, registers the global error handler. Adds /health (alive) and /ready (deps). No rules here.
