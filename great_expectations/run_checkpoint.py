"""
Contract layer 3: row-level data quality on top of the Gold mart.

Layers 1 (Apicurio Avro compatibility) and 2 (dbt Model Contracts) both stop
at *shape* — a column exists, has the right name, has the right type. Neither
one can say anything about whether the values inside that column make sense.
`gold_order_summary.status` is declared `varchar` in dbt's contract (schema.yml)
and nothing in Postgres, Debezium, or dbt enforces which strings are valid
order statuses — a stray `UPDATE shop.orders SET status = 'shpped'` (typo,
direct SQL, no application-layer validation) would sail through both of those
layers untouched and land in the Gold table exactly as typed. That's the gap
this layer closes: real business-rule checks (allowed value sets, non-negative
amounts, uniqueness) evaluated against actual Trino/Iceberg query results, not
just static schema metadata. See ADR 0020 for the version/API research behind
this script and ADR 0019/0012 for how layers 1 and 2 work.

Uses GX Core's Fluent Datasource API (`context.data_sources.add_sql(...)`)
against Trino via the `trino[sqlalchemy]` dialect — verified directly against
docs.greatexpectations.io/docs/core/introduction/try_gx (SQL-table workflow
example) rather than assumed from an older GX version's API, since GX's
Python API changed substantially between the 0.x and 1.x lines.
"""

import sys
import time

import great_expectations as gx
from great_expectations.checkpoint.checkpoint import Checkpoint
from great_expectations.core.expectation_suite import ExpectationSuite
from great_expectations.core.validation_definition import ValidationDefinition
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

# Same Trino coordinates dbt's profiles.yml uses (host: trino, port: 8080,
# no auth — method: none in dbt's profile maps to an unauthenticated
# connection here too). `iceberg` is the catalog, `gold` the schema.
TRINO_CONNECTION_STRING = "trino://gx@trino:8080/iceberg/gold"

PUSHGATEWAY_ADDRESS = "pushgateway:9091"

# Scoped to pass/fail + duration only (not a numeric violation count): the
# CheckpointResult's internal per-expectation structure hasn't been
# inspected/verified against a live run this session, and `result.success`
# is the one signal this script's own exit-code logic already proves
# correct. Extending this to a real "N values violated" count is a
# documented follow-up in ADR 0024, not a guess shipped now. See ADR 0024.

ALLOWED_ORDER_STATUSES = ["placed", "shipped", "delivered", "cancelled"]


def build_suite() -> ExpectationSuite:
    suite = ExpectationSuite(name="gold_order_summary_quality")

    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToNotBeNull(
            column="order_id", severity="critical"
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeUnique(
            column="order_id", severity="critical"
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToNotBeNull(
            column="customer_id", severity="critical"
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="status",
            value_set=ALLOWED_ORDER_STATUSES,
            severity="critical",
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


def main() -> None:
    context = gx.get_context()

    data_source = context.data_sources.add_sql(
        "trino_gold", connection_string=TRINO_CONNECTION_STRING
    )
    data_asset = data_source.add_table_asset(
        name="gold_order_summary", table_name="gold_order_summary"
    )
    batch_definition = data_asset.add_batch_definition_whole_table(
        "gold_order_summary_batch"
    )

    suite = context.suites.add(build_suite())

    validation_definition = context.validation_definitions.add(
        ValidationDefinition(
            name="gold_order_summary_validation",
            data=batch_definition,
            suite=suite,
        )
    )

    checkpoint = context.checkpoints.add(
        Checkpoint(
            name="gold_order_summary_checkpoint",
            validation_definitions=[validation_definition],
        )
    )

    start = time.time()
    result = checkpoint.run()
    duration = time.time() - start
    print(result.describe())

    push_metrics(duration_seconds=duration, success=result.success)

    if not result.success:
        print("\nGX CHECKPOINT FAILED — see failed expectation(s) above.")
        sys.exit(1)

    print("\nGX CHECKPOINT PASSED — all expectations satisfied.")
    sys.exit(0)


def push_metrics(duration_seconds: float, success: bool) -> None:
    registry = CollectorRegistry()
    Gauge(
        "gx_checkpoint_duration_seconds",
        "Wall-clock time of the gold_order_summary checkpoint run",
        registry=registry,
    ).set(duration_seconds)
    Gauge(
        "gx_checkpoint_success",
        "1 if the last checkpoint run passed, 0 if it failed",
        registry=registry,
    ).set(1 if success else 0)
    try:
        push_to_gateway(PUSHGATEWAY_ADDRESS, job="great_expectations", registry=registry)
    except OSError as exc:
        # An observability hiccup must never mask, or change the exit code
        # of, the real checkpoint result — this function's caller decides
        # sys.exit() based on `result.success`, not on whether this push
        # succeeded.
        print(f"warning: failed to push metrics to Pushgateway: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
