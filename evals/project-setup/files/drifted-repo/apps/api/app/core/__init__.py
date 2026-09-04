# Cross-cutting primitives every domain may use: security.py (argon2, JWT sign/verify with JWT_SIGNING_KEY),
# redis_client.py, rate limit. No domain logic here. A domain never imports another domain's internals; it imports core.
