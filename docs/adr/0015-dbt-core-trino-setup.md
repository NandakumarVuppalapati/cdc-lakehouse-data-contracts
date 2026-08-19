# ADR 0015: dbt Core (dbt-trino) for Silver/Gold, contract enforced on Gold

Status: Accepted
Date: 2026-08-11

## Context
Tier 1's transformation layer (contract layer 2 in docs/architecture.md)
needed dbt Core running against the existing Trino/Iceberg setup, building
Bronze &#8594; Silver &#8594; Gold. Chose to build this before Apicurio (contract
layer 1) specifically because dbt only depends on Trino, which is now
stable after tonight's Nessie/kafka-connect debugging — Apicurio would mean
reconfiguring the Kafka Connect converters (JSON &#8594; Avro) on a pipeline
that just got hard-won stability, a bigger risk to take on the same night.

Verified `dbt-trino`'s current compatible version (1.10.2, against
dbt-core ~1.11.x) and the exact `profiles.yml` field names against the
official dbt docs before writing the Dockerfile/profile, rather than
guessing — consistent with how the rest of this session's costly mistakes
got fixed (ADR 0007, 0012, 0013).

## Decisions

**dbt runs as a one-shot Docker service, not `up -d`.** `docker compose up
dbt` just prints the version (harmless smoke test); real usage is
`docker compose run --rm dbt <command>`. dbt commands are inherently ad hoc
(`run`, `test`, `build`), unlike the always-on services in this stack.

**`generate_schema_name` macro override.** dbt's default behavior
concatenates the profile's target schema with a model's `+schema` config
(e.g. target `silver` + model config `gold` &#8594; table lands in `silver_gold`,
not `gold`). Overrode it to use the custom schema name verbatim. This is a
well-known dbt gotcha — worth catching before the first real `dbt run`
produced a confusing "table not found in `gold`" when the table actually
existed in `silver_gold`, rather than after.

**Silver/Gold namespaces added to `trino-init` proactively.** Nessie
requires an explicit namespace before any table can be created in it (ADR
0011) — this applies to dbt's `CREATE TABLE AS SELECT` exactly as much as
it applied to the Iceberg sink connector. Added `silver` and `gold` schema
creation to the same `trino-init` one-shot alongside `bronze`, and made the
`dbt` service `depends_on: trino-init: condition: service_completed_successfully`
(same fix as ADR 0014) — this is the same startup-ordering bug pre-empted
in a new place rather than rediscovered.

**CDC dedup pattern in Silver.** Bronze holds the raw, un-deduplicated
Debezium event stream (every insert/update/delete as its own row, by
design — see `sources.yml`). Each Silver model collapses that to "current
state per primary key" with `ROW_NUMBER() OVER (PARTITION BY <pk> ORDER BY
ts_ms DESC)`, keeping rank 1, and drops the row entirely if the latest
event was a delete (`op != 'd'`) — soft delete, matching what a real OLTP
`DELETE` should mean by the time it reaches a business-facing table.
`COALESCE(after.<pk>, before.<pk>)` handles the fact that a delete event's
`after` struct is null; the key only survives in `before` for that one row.

**Model Contract enforced on Gold, not Silver.** `gold_order_summary` has
`contract: {enforced: true}` with explicit column types — this is the
concrete demo of contract layer 2. Silver is left uncontracted since it's
still an internal cleanup layer, closer to Bronze than to a stable
consumer-facing interface; Gold is what a dashboard or another team would
actually query, which is where a silent breaking change matters most.

## Alternatives considered
**Views instead of tables for Silver.** Cheaper (no storage duplication,
always reflects the latest Bronze data), but introduced uncertainty about
Trino's Iceberg-view support that wasn't worth resolving mid-session given
how many other edge cases already surfaced tonight. Tables via
`CREATE TABLE AS SELECT` are unambiguously supported; revisit views later
if incremental/materialized-view patterns are worth the complexity.

## Consequences
- Silver/Gold are full-refresh tables for now (`dbt run` rebuilds them
  entirely each time), not incremental — fine at this data volume, would
  need revisiting before this pattern scaled to a real dataset.
- Column types in Gold's contract (`schema.yml`) were derived from
  reasoning about Trino's type-inference rules (`from_iso8601_timestamp`
  &#8594; `timestamp(3) with time zone`, `COUNT()` &#8594; `bigint`, etc.), not
  confirmed against a live `dbt run` yet — first real run is the actual
  test of whether these are right, tracked as the immediate next step.
