# ADR 0005: Pin exact image tags, not minor-version shorthand

Status: Accepted
Date: 2026-08-07

## Context
First `docker compose up --build` failed:
```
failed to resolve source metadata for docker.io/debezium/connect:2.7: not found
```
Root cause: Debezium moved container image publishing to quay.io starting with
the 2.7.x series — docker.io/debezium/connect stopped receiving tags there
(its most recent tag is ~2 years old). Neither registry publishes a bare
`2.7` or `3.6` tag at all; only fully-qualified `<major>.<minor>.<patch>.Final`
tags exist (e.g. `3.6.0.Final`).

## Decision
- Use `quay.io/debezium/connect:3.6.0.Final` (current stable as of Aug 2026,
  built against Kafka Connect 4.3.0).
- Upgrade `apache/kafka` to `4.3.1` to match (Kafka 4.x is KRaft-only anyway,
  which is what this project already used).
- Upgrade `trinodb/trino` to the pinned release `483` instead of `:latest`.
- Bump the Iceberg Kafka Connect runtime to `1.11.0` to match.

## Consequences
Every image tag in this repo now resolves to an exact, reproducible version —
a `docker compose up` today and one six months from now pull the same bits.
The trade-off is manual upkeep: registries move (as this incident shows), so
tags need occasional revalidation rather than trusting `:latest` to always
do the right thing. Worth it for a project whose entire premise is "don't
let things silently drift out from under you."
