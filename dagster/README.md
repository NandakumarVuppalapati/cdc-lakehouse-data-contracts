# Dagster orchestration

Software-defined assets modeling the dbt project (Bronze sources -> Silver
-> Gold, one multi-asset per `@dbt_assets`) with the Great Expectations
checkpoint wired in as a blocking asset check on `gold/gold_order_summary`.
See ADR 0003 for why Dagster over Airflow, and ADR 0022 for the version
research and API choices in `definitions.py`.

## Run it

```
docker compose up -d dagster
```

Then open http://localhost:3000. Click "Materialize all" to run the full
dbt build + GX check from the UI, or select `gold_order_summary` and
materialize just that asset and its upstream dependencies.

This doesn't replace the standalone `docker compose run --rm dbt run` /
`... great-expectations` commands — both still work independently. Dagster
is an additional unified view and trigger point on top of the same dbt
project and GX suite, not a replacement for either.

## Files

- `definitions.py` — the whole asset graph: `DbtProject`/`@dbt_assets` for
  the dbt models, `@asset_check` for the GX suite. Bind-mounted into the
  container at runtime, not baked into the image.
- `requirements.txt` — pinned `dagster`/`dagster-dbt`/`dbt-trino`/
  `great_expectations`/`trino[sqlalchemy]` versions.
- `Dockerfile` — thin `python:3.11-slim` base running `dagster dev` (webserver
  + daemon together — a standalone `dagster-webserver` doesn't process the
  run queue, see ADR 0022).
