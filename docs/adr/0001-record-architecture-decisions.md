# ADR 0001: Record architecture decisions

Status: Accepted
Date: 2026-08-07

## Context
This project makes several non-obvious tool choices (Nessie over Polaris,
Dagster over Airflow, Apicurio over Confluent Schema Registry, KRaft over
ZooKeeper). A tool list doesn't communicate *why* — and the reasoning is
the actual signal for a hiring manager reading this repo, not the list.

## Decision
Every non-default choice gets a short ADR in this folder using `template.md`.

## Consequences
Slightly more writing per decision. In exchange, the repo reads as engineered,
not assembled — someone reviewing it can see the trade-offs were actually
considered.
