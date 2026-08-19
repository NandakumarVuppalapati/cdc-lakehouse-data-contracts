# ADR 0006: Install connector plugins via confluent-hub, not a hand-built Maven download

Status: Superseded by ADR 0007 (the Iceberg half only — the Debezium
confluent-hub install in this ADR still stands and works)
Date: 2026-08-07

## Context
After fixing the Debezium image tag (ADR 0005), the build failed again:
```
curl: (22) The requested URL returned error: 404
.../iceberg-kafka-connect-runtime/1.11.0/iceberg-kafka-connect-runtime-1.11.0.zip
```
Investigation (Maven Central search API, `numFound: 0`; a still-open upstream
issue at github.com/apache/iceberg/issues/11685) confirmed Apache Iceberg does
**not** publish a shaded/bundled Kafka Connect plugin zip to Maven Central.
What is there (`org.apache.iceberg:iceberg-kafka-connect`) is a bare library
jar with no dependencies bundled — not usable as a drop-in Connect plugin.

## Decision
Switch the Kafka Connect image from `quay.io/debezium/connect` (custom curl
install) to `confluentinc/cp-kafka-connect:8.2.2`, and install both
connectors the way the wider ecosystem actually does — via the `confluent-hub`
CLI, which is built into Confluent's image and resolves pre-built plugin
distributions from Confluent's own CDN:
```
confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest
confluent-hub install --no-prompt tabular/iceberg-kafka-connect:0.6.19
```
Confirmed working as of a July 2025 write-up reproducing this exact pipeline
(rmoff.net). Note the connector class is `io.tabular.iceberg.connect.IcebergSinkConnector`
— the Iceberg sink was authored by Tabular and later contributed to the
Apache Iceberg project, but as of this writing the Confluent Hub listing
(under the `tabular` namespace) is still the actual working distribution
channel, despite being marked "deprecated." The Apache-native package path
isn't independently distributable yet (see the context above).

## Alternatives considered
**Build the Iceberg Kafka Connect runtime from source via Gradle**
(multi-stage Docker build, cloning apache/iceberg and running the connect
runtime's `distZip` task). More "correct" in principle — no dependency on a
third-party download — but adds a slow, fragile Gradle build to the image
build path for a Tier 0 goal of "get one CDC event flowing end to end."
Revisit if the Confluent Hub channel for this connector ever actually
disappears rather than just being marked deprecated.

## Consequences
Two extra layers of indirection to be aware of: (1) if Confluent ever
retires the deprecated Tabular listing outright, this breaks and the
from-source build becomes necessary; (2) `debezium/debezium-connector-postgresql:latest`
is intentionally not pinned yet — needs a follow-up ADR once a specific
version is confirmed compatible with Debezium's own release cadence,
tracked as a known gap rather than silently left inconsistent with ADR 0005's
"pin everything" principle.
