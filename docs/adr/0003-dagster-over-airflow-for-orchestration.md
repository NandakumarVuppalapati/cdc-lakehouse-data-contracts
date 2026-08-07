# ADR 0003: Dagster over Airflow for orchestration

Status: Accepted
Date: 2026-08-07

## Context
Need to orchestrate: monitor CDC/sink health, trigger dbt runs, run Great
Expectations checkpoints, and expose the result as a lineage graph.

## Decision
Use Dagster for Tier 1 orchestration.

## Alternatives considered
**Apache Airflow** — still the enterprise default and the safer "expected"
answer on a resume; task-based DAGs are less natural for modeling "this
Iceberg table is an asset with a contract" than Dagster's asset-centric model.

## Consequences
Dagster's Software-Defined Assets map directly onto "each Iceberg table is a
contracted asset with upstream/downstream lineage," which is the core story
of this project — the lineage graph becomes a demo artifact almost for free.
Trade-off: Airflow is more likely to be the tool a given employer already
runs, so the README explicitly notes working Airflow knowledge separately
rather than assuming Dagster experience transfers 1:1.
