# ADR 0011: Nessie requires explicit namespace creation

Status: Accepted
Date: 2026-08-11

## Context
After fixing the `route-field` misconfiguration (a real Kafka Connect message
routing bug, not a Nessie issue), the sink connector's tasks still crashed,
now with:
```
org.apache.iceberg.exceptions.NoSuchNamespaceException: Namespace does not exist: bronze
Caused by: org.projectnessie.error.NessieReferenceConflictException: Namespace 'bronze' must exist.
```
`iceberg.tables.auto-create-enabled=true` only auto-creates *tables*. Nessie,
unlike Hive Metastore or AWS Glue, enforces that the parent namespace already
exist — it will not implicitly create one as a side effect of a table commit.

## Decision
Add a one-shot `trino-init` service that runs `CREATE SCHEMA IF NOT EXISTS
bronze` against the Iceberg/Nessie catalog via Trino, once Trino is healthy
and before anything tries to write. Chose Trino as the executor since it's
already wired to the same catalog and its SQL `CREATE SCHEMA` is the
simplest way to create a Nessie namespace without adding a direct
dependency on Nessie's own REST API shape.

## Consequences
Bronze namespace now gets created automatically on every fresh `docker
compose up`, not just this one time by hand. When Tier 1's silver/gold
layers land, their namespaces need adding to this same init step.

Known related gap, not fixed here: Nessie's version store is still
`IN_MEMORY` (see ADR 0002), so a Nessie container restart wipes catalog
metadata the same way Kafka did before ADR 0010's volume fix — this
`trino-init` step is what makes that survivable (namespace just gets
recreated), but any tables/data committed before the restart are still
gone. Worth revisiting with a persistent version store (RocksDB or
Postgres-backed) before this project is used for anything beyond active
development — deliberately not guessing at that config here without
verifying it first, given how many of the fixes in this session came from
verifying instead of assuming.
