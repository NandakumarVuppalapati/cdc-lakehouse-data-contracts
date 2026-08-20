# Chaos testing

`kafka_broker_chaos_test.py` — kills the single Kafka broker mid-flight,
confirms Debezium's source connector and the four Iceberg sink connectors
actually recover, and measures how long that takes. See
`docs/adr/0027-kafka-broker-chaos-test.md` for the full design writeup.

## Running it

Bring the full stack up and register connectors first:

```bash
docker compose up -d
./scripts/register-connectors.sh
```

Then, from the repo root:

```bash
python chaos/kafka_broker_chaos_test.py
```

Stdlib-only — no `pip install` needed. Prints every state transition it
observes as it happens, then a final data-loss check query to run in
Trino (http://localhost:8082).
