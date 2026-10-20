# The rules of users. Calls its own repository and other domains' services. Never another domain's repository. No HTTP.
# Sign-in looks up the account, then calls app.core.auth.refuse_reserved before it checks the
# password, so the reserved `default` user can never sign in. me(principal) returns the user and
# principal.development, so the UI can show that it runs as the development identity.
