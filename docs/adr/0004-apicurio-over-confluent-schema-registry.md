# ADR 0004: Apicurio Registry over Confluent Schema Registry

Status: Accepted
Date: 2026-08-07

## Context
Need schema-compatibility enforcement between Debezium's Avro output and
Kafka, as the first of three contract-enforcement layers.

## Decision
Use Apicurio Registry.

## Alternatives considered
**Confluent Schema Registry** — community edition is free, but its license
restricts building software that competes with Confluent's own products,
and it only supports Kafka as a storage backend.

## Consequences
Apicurio is fully open source (Apache 2.0), supports Postgres/in-memory/Kafka
storage backends, and has a native "Data Contracts" metadata model (owner,
status, domain, classification) that maps directly onto this project's theme.
No meaningful downside for a self-hosted, free-tier project.
