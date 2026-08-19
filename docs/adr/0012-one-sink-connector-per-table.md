# ADR 0012: One Iceberg sink connector per table, not one connector for all four

Status: Accepted
Date: 2026-08-11

## Context
The single `shop-iceberg-sink` connector (4 topics → 4 tables via parallel
`topics`/`iceberg.tables` lists, no `route-field`) produced real, silent
data corruption: `bronze.orders` ended up created with `order_items`'
schema (`order_item_id`, `product_id`, `quantity`, `unit_price_cents`) — a
record from the wrong topic created the wrong table.

Fetched the actual upstream README
(`github.com/databricks/iceberg-kafka-connect`, formerly `tabular-io`) rather
than trust secondhand summaries at this point. Every documented multi-table
example routes from a **single** topic using `iceberg.tables.route-field` +
`iceberg.table.<name>.route-regex` (static fan-out) or dynamic routing.
There is no documented example — and apparently no real support — for
"N topics, N tables, matched positionally, no routing." What looked like a
reasonable inference from the config shape (parallel comma-lists) wasn't
actually how the connector works.

## Decision
Run one sink connector per table, each with a single `topics` value and a
single `iceberg.tables` value — exactly the documented "single destination
table" pattern, four times over:
`iceberg-sink-customers`, `iceberg-sink-products`, `iceberg-sink-orders`,
`iceberg-sink-order-items`. `tasks.max` dropped to `1` per connector (each
only has one topic-partition to consume; running 2 tasks bought nothing but
did add the internal transactional-producer overhead that caused ADR
0010's issue).

## Alternatives considered
**Single topic + CDC field/dynamic routing** — would require re-keying all
four entity types into one Kafka topic with a discriminator field, a much
bigger structural change to the Debezium side for no real benefit here
(our four entities are genuinely independent streams, not variants of one
event type).

## Consequences
Four connectors to manage instead of one — more entries in
`register-connectors.sh`, more entries in Dagster's asset graph once Tier 1
lands (arguably a feature: each table's ingestion is now an independently
failing/restartable unit, closer to how you'd actually want this in
production). The two tables that got corrupted by the old connector
(`bronze.orders`, `bronze.customers`) need dropping and recreating fresh —
tracked as the immediate next step, not fixed by this ADR alone.
