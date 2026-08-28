#!/usr/bin/env bash
# ctl migrate new "<message>" — create an empty revision in apps/database/postgres/migrations/versions/.
# No --autogenerate: two backends consume this schema, so revisions are hand-written.
