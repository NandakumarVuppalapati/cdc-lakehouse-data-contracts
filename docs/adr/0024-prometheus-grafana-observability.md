# ADR 0024: Prometheus + Grafana — real metrics, pull for long-running, push for batch

Status: Accepted (design verified against docs/existing scripts; **not yet
run** — see Consequences, same caveat as ADR 0023)
Date: 2026-08-19

## Context
`docs/architecture.md` and `observability/README.md` have listed
"consumer lag, dbt run duration, contract-violation counts" as the target
metrics since Tier 0. Two shapes of thing need monitoring here, and they
don't fit the same collection model:

- **Kafka consumer lag** is a property of a long-running process (the
  Iceberg sink connectors' internal consumers) — a natural Prometheus
  *pull* target.
- **dbt build results** and **the GX checkpoint result** are properties of
  short-lived, one-shot containers (`docker compose run --rm dbt build`,
  `... great-expectations`) that exit before Prometheus's next scrape
  could ever reach them. Prometheus's own docs are explicit that this
  shape needs Pushgateway, not a scrape target — pulling doesn't work when
  the thing being measured is already gone by the time you'd pull.

## Decision
Four new services (`docker-compose.yml`): `prometheus`, `pushgateway`,
`kafka-exporter`, `grafana`.

**Versions, checked against real sources, not memory:**
- `prom/prometheus:v3.13.2` — latest non-RC tag on Docker Hub at the time
  of writing. The unsuffixed tag shares its image digest with the
  explicit `-busybox` tag (confirmed by comparing SHAs on the tags page),
  which matters directly: the healthcheck below (`wget -qO-
  http://localhost:9090/-/ready`) only works because this image actually
  ships busybox's `wget`, not because every Prometheus image does.
- `prom/pushgateway:v1.11.3` — latest release (2026-05-27).
- `grafana/grafana:12.4.8` — latest 12.4.x patch (2026-08-07). Deliberately
  `grafana/grafana`, not `grafana/grafana-oss` — Grafana Labs stopped
  updating the `-oss` repo as of the 12.4.0 release, confirmed via
  Grafana's own release notes.
- `danielqsj/kafka-exporter:v1.9.0` — latest release (2025-02-17), 2.5k
  GitHub stars, CI still green, actively maintained project (not
  abandoned — checked commit/release history before pinning).
- `prometheus-client==0.25.0` (Python) — latest PyPI release, added to
  `great_expectations/requirements.txt` and `dagster/requirements.txt`.

**Kafka consumer lag** (`kafka-exporter`, scraped by Prometheus): points
at the broker directly (`--kafka.server=kafka:29092`), filtered to
`--group.filter=connect-shop-.*`. Kafka Connect's default sink-connector
consumer group naming is `connect-<connector-name>` — confirmed via
search against Connect docs/community references, not assumed — so this
catches exactly the four `shop-iceberg-sink-*` connectors' groups
(`kafka_consumergroup_lag_sum`) and excludes internal noise
(`__consumer_offsets` etc.) that would otherwise dominate the exporter's
own metadata refresh cost.

**dbt build metrics**: `dbt/run_with_metrics.py`, a new stdlib-only Python
wrapper that replaces `dbt` as the image's `ENTRYPOINT`. Times the real
`dbt` subprocess, pushes `dbt_build_duration_seconds` /
`dbt_build_success` to Pushgateway under `job=dbt_build`, and separately
parses `target/run_results.json` — dbt's own documented, stable artifact
schema (not internal/undocumented) — to count `test.*` results with
`status` not in `("pass", "skipped")` as `dbt_test_failures`. This is the
"contract-violation count" metric the original plan called for: dbt's
`not_null`/`unique` data tests (the ones dagster-dbt already surfaces as
asset checks) failing is a real, countable signal, distinct from a Model
Contract violation (which fails the whole `dbt build` invocation and
already shows up in `dbt_build_success` — deliberately not double-counted
here). Transparent wrapper: every existing usage
(`docker compose run --rm dbt build/test/run`, the compose file's default
`--version`) behaves exactly as before; argv passes straight through,
exit code is dbt's exit code.

**GX checkpoint metrics**: `great_expectations/run_checkpoint.py` now
times `checkpoint.run()` and pushes `gx_checkpoint_duration_seconds` /
`gx_checkpoint_success` under `job=great_expectations`, using
`prometheus_client`'s `push_to_gateway`. **Deliberately scoped to
pass/fail, not a numeric violation count.** A real "N values failed
expect_column_values_to_be_in_set" count would need inspecting
`CheckpointResult`'s per-expectation result structure
(`result.run_results` / nested `ExpectationValidationResult` objects) —
that structure hasn't been verified against a live run this session, only
`result.success` and `result.describe()` have (both already proven inside
this exact function). Guessing at attribute names for a metric nobody has
actually seen come out of a real run would break this project's own
"verify before writing" discipline, so it's left out rather than shipped
unverified. If someone inspects a live `CheckpointResult` object later
(the next real `docker compose run --rm great-expectations`, e.g. via a
quick `print(vars(result))`), extending this to a real count is a small
follow-up, not a redesign.

**Dagster-triggered runs get the same metrics**, duplicated (not
imported) into `dagster/definitions.py` under `job=dbt_build_dagster` /
`job=great_expectations_dagster` — same separate-images-separate-
dependency-sets rationale as ADR 0022's GX-suite duplication. The Dagster
side skips the `dbt_test_failures` count specifically: it invokes dbt via
`DbtCliResource`/`dbt.cli(...)`, not a plain subprocess, and this
session didn't verify where that leaves `run_results.json` relative to a
predictable cwd — scoped down for the same "don't guess" reason as the GX
violation count above.

**Grafana**: one dashboard (`observability/grafana/dashboards/
lakehouse-overview.json`), one datasource, both provisioned from mounted
files rather than clicked together — panels: Iceberg sink consumer lag
(timeseries), dbt build duration (timeseries), last dbt build result
(stat, pass/fail), dbt test failures (stat), last GX checkpoint result
(stat, pass/fail), GX checkpoint duration (timeseries). Anonymous Viewer
access enabled (`GF_AUTH_ANONYMOUS_ENABLED`) — this is a local demo
project, not internet-exposed, and it means a portfolio screenshot shows
the dashboard directly instead of a login screen. Host port `3001` (not
Grafana's default `3000`) — that port is already Dagster's in this stack.

## Alternatives considered
- **JMX Prometheus exporter as a Java agent on Kafka Connect**, to get
  Connect-specific task/connector metrics rather than just consumer lag.
  Would mean modifying the already-nontrivial multi-stage
  `kafka-connect/Dockerfile` (ADR 0006/0007/0008's four-failed-attempts
  image) to wire in `KAFKA_JMX_OPTS`, download the JMX exporter jar, and
  maintain a metric-mapping YAML — real value, but real added complexity
  on top of an image that's already been fragile once. `kafka-exporter`
  gets the one metric this project's plan actually called for (consumer
  lag) at a fraction of the setup cost. Left as a follow-up if
  Connect-level metrics (rebalances, task restarts) become worth the
  cost.
- **Textfile collector instead of Pushgateway** for the dbt/GX batch
  metrics (write a `.prom` file to a shared volume, have a
  `node_exporter` sidecar serve it): more moving parts (a volume shared
  across three otherwise-independent images, a fifth new service) for the
  same outcome Pushgateway gives natively and is explicitly documented
  for. Pushgateway is the simpler, better-fit tool here.
- **A numeric GX violation count now, best-effort**: rejected — see the
  "Deliberately scoped" paragraph above. Better to ship an honestly
  smaller metric than a guessed-at one.

## Consequences
- **Not yet run.** Same caveat as ADR 0023: no GitHub remote is
  configured and this session's tooling can't drive the user's own Docker
  Desktop directly (click-tier-only terminal access — the standing
  platform restriction this whole project has worked within). Every piece
  here is built against confirmed image tags, documented metric names
  (`kafka_consumergroup_lag_sum`, dbt's `run-results.json` schema), and
  proven-working code paths from this project's own prior sessions (the
  exact GX suite, the exact `result.success` usage) — but "designed
  carefully" isn't "observed working." First real
  `docker compose up -d prometheus pushgateway kafka-exporter grafana`
  should be treated as a debugging pass, most likely failure points:
  whether `kafka-exporter` actually sees a populated consumer group before
  the first sink commit (10s interval, per `iceberg-sink-orders.json`) has
  happened at least once, and whether the Prometheus healthcheck's `wget`
  assumption holds.
- `11-grafana-dashboard.png` stays `[ ]` in PORTFOLIO_ASSETS.md until a
  real run produces a dashboard worth screenshotting.
- Three more images pulled/built alongside the existing eleven — a real,
  if modest, addition to `docker compose up -d`'s total memory/startup
  footprint, on top of the CI resource-pressure concern already flagged in
  ADR 0023. Not included in `.github/workflows/ci.yml`'s service list
  (that workflow doesn't start `prometheus`/`grafana`/etc.) specifically
  to avoid adding to that pressure — observability isn't part of what
  CI's breaking-change assertion needs to prove.
