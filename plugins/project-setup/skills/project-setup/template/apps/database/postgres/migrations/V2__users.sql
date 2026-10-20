-- The accounts the api authenticates. A table that records an owner references users(id).
-- A null password_hash means the account has no password sign-in.
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username text NOT NULL UNIQUE,
    password_hash text,
    created_at timestamptz NOT NULL DEFAULT now()
);
