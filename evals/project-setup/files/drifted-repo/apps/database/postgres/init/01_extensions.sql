-- Runs once, on an empty pgdata, in file-name order. Extensions and roles only; the schema is
-- owned by migrations (ctl migrate). Re-creating the database from a backup does not re-run this.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
