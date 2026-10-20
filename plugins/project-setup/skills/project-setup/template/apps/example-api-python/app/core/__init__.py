# Cross-cutting primitives every domain may use: security.py (argon2, JWT sign/verify with JWT_SIGNING_KEY),
# redis_client.py, rate limit. No domain logic here. A domain never imports another domain's internals; it imports core.
# auth.py decides who a request acts as and holds the AUTH_ENABLED rules. Token issuance in
# security.py calls auth.refuse_reserved first, so no token can name the reserved user.
