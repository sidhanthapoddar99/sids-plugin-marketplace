# SQL for users. Every function takes a connection; the caller owns the transaction. No rules, no HTTP.
# The reserved `default` row comes only from the migration V3__development_identity.sql: read it by
# app.core.auth.RESERVED_USER_ID, and never insert, update or delete it here.
