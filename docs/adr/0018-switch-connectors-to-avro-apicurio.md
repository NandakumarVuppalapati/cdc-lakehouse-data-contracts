# ADR 0018: Switch all 5 connectors from JsonConverter to Avro/Apicurio

Status: Accepted
Date: 2026-08-12

## Context
With Apicurio Registry up and healthy (ADR 0016) and its Avro converter
plugin baked into the `kafka-connect` image, this switches the actual data
path: the Debezium source and all 4 Iceberg sink connectors move from
`org.apache.kafka.connect.json.JsonConverter` (raw JSON schema embedded in
every message, nothing validated) to
`io.apicurio.registry.utils.converter.AvroConverter` (schema registered
once in Apicurio, referenced by ID, actually enforceable). Verified the
exact per-converter property names against a second source (not just the
single Debezium doc page cited in ADR 0016) before writing these configs:
`key.converter.apicurio.registry.url` /
`value.converter.apicurio.registry.url`, `...apicurio.registry.auto-
register`, `...apicurio.registry.find-latest` — Kafka Connect's standard
`key.converter.*` / `value.converter.*` namespacing, consistent with how
`key.converter.schemas.enable` already worked for JsonConverter in the old
configs.

## Decision
**Cutover, not a live migration.** The existing Kafka topics
(`shop.shop.customers`, `.products`, `.orders`, `.order_items`) contain
JSON-encoded messages from every prior test in this project. A sink
connector reconfigured to Avro would try to Avro-decode any unread backlog
in those topics and fail immediately — and even with zero backlog today,
leaving old JSON bytes at low offsets in a topic that's nominally
"Avro now" is a latent landmine, not a real fix. Rather than gamble on "no
backlog right now," the topics get deleted and recreated clean
(`topic.creation.enable` on the source connector rebuilds them
automatically on first write). This is a legitimate choice for a
dev/demo environment specifically because Postgres remains the source of
truth and the already-committed Bronze Iceberg tables already hold the
historical state — nothing is lost, only the Kafka layer's transient
JSON-encoded copy is discarded.

**Connector names kept identical**
(`shop-postgres-source`, `shop-iceberg-sink-customers`, etc.). Kafka
Connect's offset tracking is per connector name + topic partition, not
per-converter — reusing the names means `docker compose`/the register
script don't need any changes beyond the JSON files themselves, and the
delete-then-recreate step through the REST API is a clean, complete reset
rather than a partial state carried across the converter change.

**No re-snapshot.** `snapshot.mode` stays `initial`, but since the
Debezium connector's own offset (stored in Kafka Connect's internal
`lakehouse-connect-offsets` topic) already reflects a completed initial
snapshot from earlier sessions, re-registering the connector under the
same name resumes from the WAL position rather than re-snapshotting
existing rows. A fresh `INSERT` after re-registration is the actual
end-to-end proof this works — consistent with how every previous "does
this actually work" check in this project has been a real write followed
by a real read, not an assumption.

## Consequences
- Bronze Iceberg tables are unaffected structurally — Avro-decoded and
  JSON-decoded messages produce the same Kafka Connect `Struct`
  representation downstream, so the sink connector's Iceberg-write path
  doesn't change at all, only how it deserializes the Kafka message before
  that point.
- This does not yet configure a compatibility rule in Apicurio — with
  `auto-register=true` and no rule, an incompatible schema change would
  currently just register silently as a new version, not get rejected.
  That's task #16 (the actual rejection demo), tracked separately and not
  yet done.
- The two `_deprecated: true` connector JSON files
  (`iceberg-sink.json`, `iceberg-sink-config-only.json`, see ADR 0012)
  were left untouched — they're inert placeholders, not live configs.

## Verification
Confirmed end-to-end, not just "connectors show RUNNING":
`INSERT INTO shop.products (sku, name, price_cents, category) VALUES
('SKU-AVRO-TEST', ...)` on Postgres produced a real Iceberg commit
(`addedRecords=1, totalRecords=6` in the kafka-connect logs) within one
commit interval, and the row is queryable in `bronze.products` via Trino
with the correct values (`op='c'`, `sku='SKU-AVRO-TEST'`, etc.). Apicurio's
`/apis/registry/v3/search/artifacts` shows registered Avro schema
artifacts (Debezium's `Envelope` and `block` types among them), confirming
schemas are actually being registered through the new converter, not just
that the pipeline happens to still move bytes.

One thing worth remembering for next time: `docker exec lakehouse-kafka-
connect curl http://localhost:8081/...` fails with connection refused —
`localhost` inside a container is that container's own loopback, not the
host. The 8081 host-port mapping only resolves from outside Docker; from
inside another container on `lakehouse-net`, Apicurio is reachable at
`http://apicurio:8080` (its container-internal port), which is exactly
what the connector configs use and exactly why they worked.
