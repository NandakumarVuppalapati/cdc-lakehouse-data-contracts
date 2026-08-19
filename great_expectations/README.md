# Great Expectations — contract layer 3

Row-level data quality on `iceberg.gold.gold_order_summary`, run via GX Core
1.20.0 against Trino (`trino[sqlalchemy]` dialect — GX has no native Iceberg
connector, so this goes through Trino same as dbt does). See ADR 0020 for the
version research and API notes, and ADR 0012/0019 for how this differs from
dbt's Model Contracts (layer 2) and Apicurio's Avro compatibility rules
(layer 1): those two only check *shape* (column names/types); this layer
checks *values* — allowed status strings, non-negative amounts, uniqueness.

## Run it

```
docker compose run --rm great-expectations
```

Exits non-zero if any expectation fails (`errors.tolerance`-style behavior,
same spirit as the Kafka Connect/dbt failure modes elsewhere in this repo) —
this is what CI will hook into later.

## Files

- `run_checkpoint.py` — defines the expectation suite and runs the checkpoint.
  Bind-mounted into the container at runtime (see docker-compose.yml), not
  baked into the image, so suite changes don't require a rebuild.
- `requirements.txt` — pinned `great_expectations`/`trino[sqlalchemy]` versions.
- `Dockerfile` — thin `python:3.11-slim` base, same pattern as `dbt/Dockerfile`.

