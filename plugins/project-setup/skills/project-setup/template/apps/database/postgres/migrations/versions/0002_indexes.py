# The advanced indexes that autogenerate cannot express:
#   GIN with pg_trgm on items.title for fuzzy search
#   partial index on orders(status) WHERE status = 'open'
#   HNSW on embeddings.vector (pgvector)
#   BRIN on events(created_at)
#   updated_at trigger function + triggers
