# ADR 0007: Download the Iceberg sink connector from its GitHub release, not confluent-hub

Status: Accepted
Date: 2026-08-07

## Context
ADR 0006's plan — install the Iceberg sink via `confluent-hub install
tabular/iceberg-kafka-connect:0.6.19` — failed on the actual build:
```
Unable to find a component
Error: Component not found, specify either valid name from Confluent Hub...
```
The Debezium connector installed via the same mechanism (`confluent-hub
install debezium/debezium-connector-postgresql:latest`) worked without issue
in the same build, so this isn't a confluent-hub problem in general — the
`tabular/iceberg-kafka-connect` listing specifically has been delisted from
Confluent Hub's index, not merely marked deprecated as its still-live docs
page implies.

## Decision
Download the connector directly from its real current home:
`github.com/databricks/iceberg-kafka-connect` (moved orgs after Databricks
acquired Tabular; `tabular-io/iceberg-kafka-connect` now redirects here).
Each release publishes a pre-built, dependency-bundled zip as a GitHub
release asset — `iceberg-kafka-connect-runtime-<version>.zip` (there's also
a `-hive` variant with extra Hadoop/Hive Metastore deps we don't need).

Verified the exact URL resolves *before* changing the Dockerfile this time —
`curl -I` on
`https://github.com/databricks/iceberg-kafka-connect/releases/download/v0.6.19/iceberg-kafka-connect-runtime-0.6.19.zip`
returns a 302 with `Content-Disposition: ...filename=iceberg-kafka-connect-runtime-0.6.19.zip`,
i.e. the asset genuinely exists at that name — not just an assumption this time.

## Alternatives considered
See ADR 0006 for the confluent-hub and Maven-Central-zip alternatives, both
now ruled out. Building from source via Gradle remains the most resilient
long-term fallback if this GitHub release channel also disappears, at the
cost of a much slower image build.

## Addendum (same day)
First attempt at this ADR's Dockerfile used `unzip` to extract the
downloaded zip — exit 127, `unzip` isn't installed in
`confluentinc/cp-kafka-connect`. Switched to `jar xf`, which ships with any
JDK and this image definitely has one (it's how the Kafka Connect worker
itself runs). No new dependency to install, no more guessing about what
package manager or package name the base image uses.

## Consequences
This is a third-party GitHub release, not a package-manager-resolved
dependency — no automatic notification if it moves again. Revisit this ADR
if a future version bump ever needs a URL change; the version is exposed as
a single Dockerfile `ARG` specifically to make that a one-line edit rather
than a rediscovery exercise.
