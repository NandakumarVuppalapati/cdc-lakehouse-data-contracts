# ADR 0013: Nessie JDBC (Postgres-backed) persistence, not IN_MEMORY

Status: Accepted
Date: 2026-08-11

## Context
Nessie was running with `nessie.version.store.type=IN_MEMORY` (flagged as a
known gap back in ADR 0011, deliberately deferred at the time). Every restart
of the `nessie` container wipes all catalog metadata — namespaces, table
pointers, snapshot history — even though the underlying Parquet/Avro files
in MinIO survive. Tier 0 just got fully validated end to end; building Tier 1
(dbt, Apicurio, Great Expectations, Dagster) on top of a catalog that loses
its state on every restart risks repeating this session's multi-hour Docker
recovery cycles, but for data instead of infra config.

Verified Nessie's JDBC config against the primary source
(`projectnessie.org/nessie-latest/configuration/`) rather than guessing, given
how many earlier fixes in this project came from confirming behavior against
upstream docs instead of inferring it (ADR 0007, ADR 0012). Confirmed
environment variable mapping: `nessie.version.store.type` →
`NESSIE_VERSION_STORE_TYPE`, `quarkus.datasource.jdbc.url` →
`QUARKUS_DATASOURCE_JDBC_URL` (dots to underscores, uppercased — standard
Quarkus/SmallRye config convention). Username/password/db-kind follow the
same standard Quarkus datasource properties.

## Decision
Switch Nessie to `NESSIE_VERSION_STORE_TYPE=JDBC`, pointed at a new `nessie`
database on the same Postgres instance already running for the OLTP source
(`postgres:5432/nessie`, separate from `sourcedb`). Kept as a distinct
database rather than a schema inside `sourcedb` so catalog metadata and
source data stay independently backup-able/droppable — dropping the OLTP
tables for a demo reset shouldn't also nuke the catalog, and vice versa.
Added `postgres/00-create-nessie-db.sql` (runs before `init.sql` by
filename sort) so a fresh clone gets the `nessie` database automatically;
on the existing volume it has to be created manually once (migration step,
not automatic — Postgres only runs `docker-entrypoint-initdb.d` scripts on
first init of an empty data directory).

## Alternatives considered
**RocksDB version store** — simpler on paper (local embedded store, no
extra DB dependency), but its exact config properties weren't confirmed
against a primary source in this pass (the docs page's RocksDB section
didn't render through the fetch tooling used), and this project already paid
for several guessed-config failures earlier (ADR 0006, ADR 0007, ADR 0012).
Went with the option that was actually verified rather than the option that
looked simpler. Reusing the existing Postgres instance also avoids adding a
new service/volume to the compose file.

**Dedicated Postgres instance just for Nessie** — unnecessary resource
overhead for a laptop-scale demo; reusing the existing `postgres` container
is pragmatic here, at the cost of coupling Nessie's availability to the same
container as the OLTP source (acceptable for this project's scope).

## Follow-up: trino-init raced Nessie's restart
Applying this migration on the running stack exposed a second, related gap:
Nessie has no `healthcheck` in this compose file, and `trino-init` only
`depends_on: trino: condition: service_healthy` — nothing waited for Nessie
itself. On `docker compose up -d --force-recreate trino-init` right after
restarting Nessie, `trino-init` fired its `CREATE SCHEMA` before Nessie's
JDBC store had finished initializing, and failed silently (the one-shot
container just exited non-zero with no automatic retry).

Fixed by adding a `healthcheck` to the `nessie` service. Nessie's main port
(19120) has no lightweight readiness endpoint, but its Quarkus management
interface (port 9000) exposes `smallrye-health` at `/q/health/ready` —
confirmed by curling it directly rather than guessing the path. `trino` and
`kafka-connect` now both `depends_on: nessie: condition: service_healthy`
instead of `service_started`, so this race can't recur on any future
restart, not just this one.

## Consequences
- `nessie` now depends on `postgres` being healthy (`depends_on: postgres:
  condition: service_healthy`), where it previously started independently.
- Switching an *existing* IN_MEMORY catalog to JDBC starts from an empty
  catalog — old namespace/table pointers created under IN_MEMORY don't
  carry over (data files in MinIO aren't lost, just orphaned until
  re-registered). Migration path: recreate the `bronze` namespace via
  `trino-init`, then delete and re-register the four Iceberg sink
  connectors — the same "new consumer group replays topic history"
  mechanism already validated when the four per-table connectors were
  first stood up (ADR 0012) backfills the data again.
- A full `docker compose down -v` still wipes everything (Postgres volume
  included, which now also holds the catalog) — persistence here is about
  surviving container restarts/crashes, not about surviving a deliberate
  volume wipe.
