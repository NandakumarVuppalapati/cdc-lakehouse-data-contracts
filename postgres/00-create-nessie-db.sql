-- Separate database for Nessie's JDBC-backed version store, kept apart from
-- `sourcedb` (the OLTP schema Debezium reads from) so catalog metadata and
-- source data have independent lifecycles. See ADR 0013.
--
-- Only runs automatically on a completely fresh `postgres_data` volume (the
-- Postgres image only executes docker-entrypoint-initdb.d scripts once, at
-- first init). On an existing volume, create it manually — see ADR 0013's
-- migration steps.
CREATE DATABASE nessie OWNER lakehouse;
