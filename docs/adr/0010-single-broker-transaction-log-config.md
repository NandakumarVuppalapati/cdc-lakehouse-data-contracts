# ADR 0010: Single-broker transaction log config + persistent Kafka volume

Status: Accepted
Date: 2026-08-08

## Context
Debezium→Kafka was confirmed working (4 real CDC messages visible via
`kafka-console-consumer`), but the Iceberg sink connector's tasks kept
dying with:
```
org.apache.kafka.common.errors.TimeoutException: Timeout expired after
60000ms while awaiting InitProducerId
```
The sink connector's internal coordinator ("committer") uses a
**transactional** Kafka producer to coordinate commits across tasks.
Kafka's transaction state log defaults to `transaction.state.log.replication.factor=3`
and `transaction.state.log.min.isr=2` — both impossible to satisfy on a
single-broker cluster, which is what this project intentionally runs (free,
laptop-sized). `InitProducerId` depends on that internal topic being usable,
so it just hangs until the client gives up.

Separately: `kafka` had no persistent volume, so every container restart
(this session hit one from an unrelated Docker Desktop crash — see the
chat log, not a project issue) wiped every topic, including Kafka Connect's
own config/offset/status topics — meaning connectors had to be re-registered
from scratch each time, and any in-flight CDC messages were lost.

## Decision
- Set `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1` and
  `KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1` (mirrors the same reasoning
  already applied to `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1`).
- Add a named volume (`kafka_data` → `/var/lib/kafka/data`) so broker state
  survives container restarts, matching what Postgres and MinIO already had.

## Consequences
These are single-node dev/demo settings, not production ones — worth
calling out explicitly in the case study later as a known, deliberate
trade-off (a real deployment would run 3+ brokers and use the real
defaults). With the volume in place, restarting the stack no longer means
re-registering connectors and losing topic history, which should make the
rest of this build meaningfully less fragile.
