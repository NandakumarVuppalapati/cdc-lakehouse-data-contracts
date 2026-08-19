# ADR 0014: kafka-connect must wait for trino-init, not just for Nessie

Status: Accepted
Date: 2026-08-11

## Context
After switching Nessie to JDBC persistence (ADR 0013), the four Iceberg
sink connectors repeatedly showed `RUNNING` status with zero rows landing
in any `bronze` table — across multiple full container restarts, a
Kafka Connect worker restart, a WSL2 clock-drift fix, and eventually a
full `docker compose down -v` volume wipe. None of those fixed it, which
was the real signal: this was never about persistence, stale catalog
clients, or a corrupted volume. It was a startup ordering bug that had
been there since ADR 0011 introduced `trino-init`, just masked before now
by how often Nessie itself was restarting during that ADR's fixes (which
happened to change the timing enough to usually win the race).

Pulling the actual task status (`GET /connectors?expand=status`) instead
of just the connector-level status finally showed it: every sink task was
`FAILED`, not `RUNNING`, with:

```
org.apache.iceberg.exceptions.NoSuchNamespaceException: Namespace does not exist: bronze
Caused by: org.projectnessie.error.NessieReferenceConflictException: Namespace 'bronze' must exist.
```

Both `trino-init` (creates the `bronze` namespace) and `kafka-connect`
(runs the sink tasks that auto-create tables inside that namespace) only
`depends_on: nessie: condition: service_healthy` — nothing ordered them
relative to *each other*. On a fast machine/warm image cache, kafka-connect
finishes its own plugin-loading startup and begins polling before
trino-init's single `CREATE SCHEMA` statement completes. The sink task's
first write attempt throws, and **Kafka Connect does not retry a FAILED
task automatically** — it stays dead until an explicit
`POST /connectors/<name>/tasks/0/restart`. Every earlier attempt to fix
this by waiting longer, restarting containers, or wiping volumes was
addressing symptoms of the same unordered race, not the race itself.

## Decision
Add `kafka-connect: depends_on: trino-init: condition:
service_completed_successfully`. This forces the dependency chain
`postgres/minio-init → nessie → trino → trino-init → kafka-connect`,
so the `bronze` namespace is guaranteed to exist before any sink task's
first poll.

## Alternatives considered
**Retry/backoff inside the connector config** — the `iceberg-kafka-connect`
sink has no built-in "wait for namespace" retry; the exception is treated
as unrecoverable by the Connect framework itself, not by the connector's
own retry logic. Not something this project's config can influence.

**A restart script that always restarts FAILED tasks after bring-up** —
treats the symptom, would need to run on every `docker compose up`, and
silently masks the same bug reappearing elsewhere (e.g. if a fifth sink
connector is added later). Fixing the actual dependency ordering is more
correct and is a one-line compose change.

## Consequences
- Startup is slightly slower (kafka-connect now waits for the full
  `nessie → trino → trino-init` chain instead of just `nessie`), acceptable
  for a local dev/demo stack.
- This same race could in principle now shift elsewhere (e.g. if another
  service both depends on Nessie and writes into a namespace trino-init
  creates) — the general lesson, not just this specific fix, is: check
  task-level status (`?expand=status`), not just connector-level status,
  before concluding something is "running fine."
