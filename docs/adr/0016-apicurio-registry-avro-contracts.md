# ADR 0016: Apicurio Registry for ingestion-layer Avro contracts

Status: Accepted (service scaffolded; converter wiring is ADR 0016's
follow-up work, tracked separately — see Consequences)
Date: 2026-08-12

## Context
Contract layer 1 (see docs/architecture.md) enforces schema compatibility
at the point data enters the pipeline — Debezium's Postgres source and the
Iceberg sink connector — rather than only downstream in dbt (contract layer
2, ADR 0015). Today both connectors run with `JsonConverter` and
`schemas.enable=true`, which embeds a JSON schema in every single Kafka
message and enforces nothing: any producer can emit any shape and Kafka
Connect will happily pass it through. Apicurio Registry is a real schema
registry — schemas are registered once, referenced by ID, and (with
compatibility rules configured) incompatible changes can be rejected at
write time instead of silently corrupting a downstream table.

Verified two things against primary sources before writing any config,
consistent with this project's established practice (ADR 0007, 0012, 0013)
of not repeating the "guessed config, burned an hour" mistake:

1. **Storage config** — Apicurio Registry docs
   (apicur.io/registry/docs/apicurio-registry/3.2.x/getting-started/
   assembly-installing-registry-docker.html): Postgres-backed storage uses
   `APICURIO_STORAGE_KIND=sql`, `APICURIO_STORAGE_SQL_KIND=postgresql`,
   `APICURIO_DATASOURCE_URL/USERNAME/PASSWORD`. Since Apicurio 3.x, all
   storage variants (in-memory, SQL, Kafka) share one container image
   (`apicurio/apicurio-registry`) — unlike 2.x, which shipped separate
   images per variant. This also confirmed the REST API for artifact
   management is versioned `/apis/registry/v3/...` in 3.x.

2. **Kafka Connect converter** — Debezium's Avro serialization docs
   (debezium.io/documentation/reference/stable/configuration/avro.html):
   converter class `io.apicurio.registry.utils.converter.AvroConverter`,
   set per-connector (not just worker-wide) via `key.converter` /
   `value.converter`, with `apicurio.registry.url` pointed at
   `/apis/registry/v2` — note this is a **different path than the v3
   artifact-management REST API** confirmed above. That's not a
   contradiction: the `/apis/registry/v2` path is a compatibility surface
   the AvroConverter client library specifically targets, kept alongside
   the v3 API for that reason, per Debezium's own current (3.6) docs. The
   REST calls this project will make directly (e.g. to configure
   compatibility rules) use v3; the converter's own URL property uses v2.

Also confirmed on Maven Central that
`io.apicurio:apicurio-registry-distro-connect-converter:3.3.1` actually
exists as a `.zip` (matching the Iceberg connector's distribution format,
so the existing alpine-downloader Dockerfile pattern applies unchanged).

## Decisions

**Postgres-backed from the start, not IN_MEMORY.** Applying the Nessie
lesson (ADR 0013) proactively — dedicated `apicurio_registry` database on
the same shared Postgres instance, created via
`postgres/00-create-apicurio-db.sql` (same pattern as
`00-create-nessie-db.sql`). No reason to rediscover "data vanished on
restart" a second time in the same project.

**Reused the multi-stage alpine-downloader Dockerfile pattern (ADR 0008)
rather than inventing a new one.** The Apicurio converter ships as a
`.zip` from Maven Central, same shape as the Iceberg connector artifact —
same `apk add curl unzip`, same `COPY --from=` into the final image. No
new failure surface introduced by trying something novel here.

**No healthcheck yet, on purpose.** Apicurio 3.x is Quarkus-based and
likely serves `/health/ready` on the management port (9000) — the same
pattern Nessie uses — but ADR 0013's actual lesson was "verify with a live
curl before writing a healthcheck," not "assume the same pattern applies
elsewhere." The service is scaffolded without one; next step is bringing
it up, curling the management port to find the real path, then adding the
healthcheck and wiring `kafka-connect depends_on apicurio: condition:
service_healthy` — the same proactive-namespace-style fix already applied
twice in this project (ADR 0011, ADR 0014).

**Host ports 8081 (API) / 9091 (management).** 8080-8083 and 9000/9001 are
already claimed by other services in this stack or by other projects on
this machine; picked the next free ports rather than reusing internal
container ports, which don't need to match host ports at all.

## Alternatives considered
**Confluent Schema Registry instead of Apicurio.** Rejected early (before
this session) — Apicurio is vendor-neutral, supports multiple schema
formats beyond Avro (useful if this project later adds Protobuf/JSON
Schema examples), and its REST API and rule model are openly documented
without a Confluent account. Not revisited here since the decision predates
this ADR.

## Consequences
- The service exists in `docker-compose.yml` and the converter binary will
  be baked into the `kafka-connect` image, but **no connector is using
  Avro/Apicurio yet** — all 5 connectors (1 source + 4 sinks) still run
  `JsonConverter`. Switching them over, verifying data still flows
  end-to-end, and configuring a compatibility rule so `auto-register=true`
  actually rejects a breaking change (rather than silently registering a
  new version) are tracked as separate follow-up work, not yet designed in
  detail — the compatibility-rule REST call in particular needs its own
  verification pass before the rejection demo can be trusted.
- Two more manual steps needed on the user's machine before this is live:
  rebuild the `kafka-connect` image (picks up the new Dockerfile stage) and
  `docker compose up -d apicurio` (brings up the new service). Both are
  additive — nothing existing changes state until the connector configs
  are actually switched in a later step.

## Follow-up (bring-up)
Two things surfaced when actually bringing the service up, both fixed and
confirmed rather than left as known issues:

1. **`FATAL: database "apicurio_registry" does not exist`.** Postgres only
   runs `docker-entrypoint-initdb.d` scripts (including
   `00-create-apicurio-db.sql`) against a completely fresh volume. This
   project's `postgres_data` volume already existed from earlier sessions,
   so the script silently never ran — the same caveat the script's own
   comment already flagged, just realized in practice instead of pre-empted
   this time. Fixed by creating the database directly against the running
   container (`docker exec ... psql ... CREATE DATABASE apicurio_registry
   OWNER lakehouse`), a one-time manual step that only matters for
   existing deployments, not fresh ones.
2. **Healthcheck path confirmed live, not guessed.** `curl
   http://localhost:9091/health/ready` (management port, mapped from
   container port 9000) returned `200` with `"status": "UP"` — Apicurio
   3.x follows the same "readiness lives on the Quarkus management port"
   pattern as Nessie (ADR 0013), but the exact path differs slightly
   (`/health/ready`, no `/q/` prefix, unlike Nessie's
   `/q/health/ready`) — confirming rather than assuming the two are
   identical was the right call. The healthcheck is now wired into
   `docker-compose.yml`, and `kafka-connect depends_on apicurio: condition:
   service_healthy` was added proactively (same lesson as ADR 0011/0014,
   applied before hitting the race this time instead of after) even though
   no connector uses Apicurio yet.

Kafka Connect's image rebuild (with the new Avro converter plugin baked
in) was also confirmed to start clean — no errors from the new plugin
being present, existing JSON-based connectors kept running normally.
