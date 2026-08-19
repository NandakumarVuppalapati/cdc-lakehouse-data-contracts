# Observability — Prometheus + Grafana

Real metrics, not simulated ones: Kafka consumer lag pulled straight from
the broker, dbt build/test results pushed from every real `dbt build`,
Great Expectations checkpoint pass/fail pushed from every real checkpoint
run. See ADR 0024 for the design (pull vs. push split, version research,
what's scoped out and why) and ADR 0022/0020 for the dbt/GX pieces this
sits on top of.

## Run it

```
docker compose up -d prometheus pushgateway kafka-exporter grafana
```

Then:
- Grafana: http://localhost:3001 (anonymous Viewer access enabled — no
  login needed to view the dashboard; admin/admin for edits)
- Prometheus: http://localhost:9090
- Pushgateway: http://localhost:9091

The dashboard populates as the pipeline actually runs — bring up the rest
of the stack, register the connectors, run `docker compose run --rm dbt
build` and `... great-expectations` (or trigger a "Materialize all" in
Dagster) to see real data points land.

## Files

- `prometheus/prometheus.yml` — scrape config: kafka-exporter (pull) +
  pushgateway (pull, holding what the batch jobs pushed).
- `grafana/provisioning/datasources/datasource.yml` — auto-registers the
  Prometheus datasource on boot.
- `grafana/provisioning/dashboards/dashboards.yml` — points Grafana at
  `grafana/dashboards/` for auto-loaded dashboard JSON.
- `grafana/dashboards/lakehouse-overview.json` — the one dashboard: Iceberg
  sink consumer lag, dbt build duration/success, dbt test failure count,
  GX checkpoint duration/success.

## What pushes metrics

- `dbt/run_with_metrics.py` — wraps every `dbt` invocation in the `dbt`
  container image, pushes `dbt_build_duration_seconds`,
  `dbt_build_success`, `dbt_test_failures` under `job=dbt_build`.
- `great_expectations/run_checkpoint.py` — pushes
  `gx_checkpoint_duration_seconds`, `gx_checkpoint_success` under
  `job=great_expectations`.
- `dagster/definitions.py` — pushes the same shape of metrics under
  `job=dbt_build_dagster` / `job=great_expectations_dagster` so a
  Dagster-triggered run is distinguishable in Grafana from a bare
  `docker compose run --rm dbt build`.
