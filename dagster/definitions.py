"""
Orchestration layer: wraps the existing dbt project and Great Expectations
checkpoint into a single Dagster asset graph, so the whole pipeline —
Bronze sources -> Silver -> Gold -> row-level quality check — shows up as
one lineage graph instead of three separately-invoked tools. See ADR 0022
for the version/API research behind this file and ADR 0003 for why Dagster
over Airflow.

This does not replace `docker compose run --rm dbt run` /
`... great-expectations` as manual verification commands — both still work
standalone. This is an additional, unified view and materialization path
on top of the same underlying dbt project and GX suite.
"""

import time
from pathlib import Path

import great_expectations as gx
from dagster import AssetCheckResult, AssetExecutionContext, Definitions, asset_check
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets
from great_expectations.checkpoint.checkpoint import Checkpoint
from great_expectations.core.expectation_suite import ExpectationSuite
from great_expectations.core.validation_definition import ValidationDefinition
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

# Same Pushgateway both the standalone dbt/great-expectations images push
# to (ADR 0024) — separate `job` labels (below) so Grafana can tell a
# Dagster-triggered run apart from a bare `docker compose run --rm dbt
# build`. Duration+success only here, not a dbt test-failure count like
# the standalone dbt wrapper has: that parses target/run_results.json by
# relative path, and this container's cwd/target-dir behavior under
# dagster-dbt's own CLI invocation hasn't been verified the way the
# standalone path has — scoped down rather than guessed. See ADR 0024.
PUSHGATEWAY_ADDRESS = "pushgateway:9091"


def _push_gauge(job: str, **metrics: float) -> None:
    registry = CollectorRegistry()
    for name, value in metrics.items():
        Gauge(name, name, registry=registry).set(value)
    try:
        push_to_gateway(PUSHGATEWAY_ADDRESS, job=job, registry=registry)
    except OSError as exc:
        # Never let an observability hiccup fail or mask a real asset
        # materialization / check result.
        print(f"warning: failed to push metrics to Pushgateway ({job}): {exc}")

# ---------------------------------------------------------------------------
# dbt: Bronze sources (from sources.yml) -> Silver -> Gold, as one multi-asset
# ---------------------------------------------------------------------------
DBT_PROJECT_DIR = Path("/dbt/cdc_lakehouse")
DBT_PROFILES_DIR = Path("/dbt/profiles")

dbt_project = DbtProject(
    project_dir=DBT_PROJECT_DIR,
    profiles_dir=DBT_PROFILES_DIR,
)
# Regenerates target/manifest.json (`dbt parse --quiet`) whenever this module
# loads under `dagster dev`/`dagster-webserver` in dev mode — confirmed this
# doesn't require a live Trino connection (dbt parse doesn't connect) before
# relying on it, since this container starts before Trino necessarily has
# the gold/silver schemas populated with data.
dbt_project.prepare_if_dev()


@dbt_assets(manifest=dbt_project.manifest_path, project=dbt_project)
def cdc_lakehouse_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    start = time.time()
    success = True
    try:
        yield from dbt.cli(["build"], context=context).stream()
    except Exception:
        success = False
        raise
    finally:
        _push_gauge(
            "dbt_build_dagster",
            dbt_build_duration_seconds=time.time() - start,
            dbt_build_success=1 if success else 0,
        )


# ---------------------------------------------------------------------------
# Great Expectations, as an asset check on the Gold asset rather than a
# separate downstream asset — Dagster's asset-check concept models "validate
# this asset's data" more directly than a second asset node would, and
# surfaces pass/fail right on the gold_order_summary node in the UI.
# Suite is identical to great_expectations/run_checkpoint.py (kept in sync
# by hand, not imported, since that script runs in its own container with
# its own dependency set — see ADR 0020/0022).
# ---------------------------------------------------------------------------
TRINO_CONNECTION_STRING = "trino://gx@trino:8080/iceberg/gold"
ALLOWED_ORDER_STATUSES = ["placed", "shipped", "delivered", "cancelled"]


def _build_gx_suite() -> ExpectationSuite:
    suite = ExpectationSuite(name="gold_order_summary_quality")
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToNotBeNull(column="order_id", severity="critical")
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeUnique(column="order_id", severity="critical")
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToNotBeNull(column="customer_id", severity="critical")
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="status", value_set=ALLOWED_ORDER_STATUSES, severity="critical"
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeBetween(
            column="total_amount_cents", min_value=0, severity="critical"
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeBetween(
            column="item_count", min_value=0, severity="critical"
        )
    )
    return suite


# `asset=["gold", "gold_order_summary"]` targets the dbt asset's actual
# Dagster key — confirmed by loading the real manifest and printing
# `defs.resolve_asset_graph().get_all_asset_keys()` before writing this,
# not assumed from the model name alone (dagster-dbt keys assets by
# schema/name, so it's "gold/gold_order_summary", not just
# "gold_order_summary"). `blocking=True` so a failing check is visually and
# functionally a gate, not just an FYI.
@asset_check(asset=["gold", "gold_order_summary"], blocking=True)
def gold_order_summary_quality_check() -> AssetCheckResult:
    context = gx.get_context()
    data_source = context.data_sources.add_sql(
        "trino_gold", connection_string=TRINO_CONNECTION_STRING
    )
    data_asset = data_source.add_table_asset(
        name="gold_order_summary", table_name="gold_order_summary"
    )
    batch_definition = data_asset.add_batch_definition_whole_table("gold_order_summary_batch")
    suite = context.suites.add(_build_gx_suite())
    validation_definition = context.validation_definitions.add(
        ValidationDefinition(
            name="gold_order_summary_validation", data=batch_definition, suite=suite
        )
    )
    checkpoint = context.checkpoints.add(
        Checkpoint(
            name="gold_order_summary_checkpoint", validation_definitions=[validation_definition]
        )
    )
    start = time.time()
    result = checkpoint.run()
    duration = time.time() - start
    _push_gauge(
        "great_expectations_dagster",
        gx_checkpoint_duration_seconds=duration,
        gx_checkpoint_success=1 if result.success else 0,
    )
    return AssetCheckResult(
        passed=result.success,
        metadata={"gx_result": str(result.describe())},
    )


defs = Definitions(
    assets=[cdc_lakehouse_dbt_assets],
    asset_checks=[gold_order_summary_quality_check],
    resources={"dbt": DbtCliResource(project_dir=dbt_project)},
)
