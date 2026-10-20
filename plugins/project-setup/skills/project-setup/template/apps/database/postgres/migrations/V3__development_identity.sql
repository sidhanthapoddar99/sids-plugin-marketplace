-- The reserved `default` user. A backend with AUTH_ENABLED=FALSE acts as it for a local request
-- that carries no credential. Its id is fixed, so every database built from these migrations
-- holds the same row, and the backends name that id as a constant.
ALTER TABLE users ADD COLUMN development_identity boolean NOT NULL DEFAULT false;

-- The marker belongs to the fixed id alone: no ordinary account can carry it, and no ordinary
-- account can take the id.
ALTER TABLE users ADD CONSTRAINT users_development_identity_fixed_id
    CHECK (development_identity = (id = '00000000-0000-4000-8000-000000000001'));

-- The reserved user never holds a password, so no sign-in form can match it.
ALTER TABLE users ADD CONSTRAINT users_development_identity_no_password
    CHECK (NOT development_identity OR password_hash IS NULL);

-- A plain INSERT. An existing account with this id or username fails the migration, so it never
-- adopts, renames or resets an ordinary account.
INSERT INTO users (id, username, password_hash, development_identity)
VALUES ('00000000-0000-4000-8000-000000000001', 'default', NULL, true);
