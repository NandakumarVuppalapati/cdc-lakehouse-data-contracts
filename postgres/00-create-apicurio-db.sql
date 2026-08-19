-- Separate database for Apicurio Registry's SQL storage backend, kept apart
-- from `sourcedb` and `nessie` for the same reason those are separate — each
-- service's metadata gets an independent lifecycle. Applying the Nessie
-- lesson (ADR 0013) proactively this time: Apicurio starts Postgres-backed
-- from the beginning, not IN_MEMORY.
--
-- Only runs automatically on a completely fresh `postgres_data` volume — see
-- postgres/00-create-nessie-db.sql for why.
CREATE DATABASE apicurio_registry OWNER lakehouse;
