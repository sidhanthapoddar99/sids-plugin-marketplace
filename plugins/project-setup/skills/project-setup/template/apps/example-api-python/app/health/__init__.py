# GET /health → alive. GET /ready → 503 unless postgres and redis answer. Unauthenticated. Compose checks /ready.
# With AUTH_ENABLED=FALSE, /ready also asks the users service whether the reserved `default` row
# exists, and names V3__development_identity.sql when it does not, because a missing row
# otherwise fails later, at the first foreign key.
