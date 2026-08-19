# ADR 0020: Great Expectations (GX Core) as contract layer 3, run via Trino

Status: Accepted
Date: 2026-08-12

## Context
Layers 1 (Apicurio Avro compatibility, ADR 0016/0018/0019) and 2 (dbt Model
Contracts, ADR 0011) both enforce *shape*: a column exists, has the declared
name, has the declared type. Neither can express a business rule like "status
must be one of these four strings" or "this amount can't be negative" — those
are checks against actual *values*, not schema metadata. `gold_order_summary`
declares `status` as `varchar` in its dbt contract, and nothing upstream
(Postgres has no CHECK constraint on `shop.orders.status`, Debezium doesn't
validate content, dbt's contract only checks type) stops a typo'd status like
`'shpped'` from a raw `UPDATE` statement from flowing all the way to Gold
untouched. That gap is what this layer closes.

GX has no native Iceberg connector as of this version — same situation dbt
was in (ADR 0009), same solution: go through Trino via SQLAlchemy, using the
same `trino` container/network dbt already queries.

**Version pinning**: didn't guess. `https://pypi.org/pypi/great-expectations/json`
and `https://pypi.org/pypi/trino/json` both returned empty output via the
fetch tool (unresolved — noted as a dead end, not retried further once the
HTML pages worked instead). Fell back to the HTML project pages and a
libraries.io mirror, which did return usable content:
- `great_expectations` — **1.20.0**, released 2026-08-07 (confirmed via
  `pypi.org/project/great-expectations/` and cross-checked against
  `libraries.io/pypi/great-expectations`, which independently listed the
  same version and release date).
- `trino` (Python client) — **0.338.0**, released 2026-06-29 (confirmed via
  `pypi.org/project/trino/`). Installed with the `[sqlalchemy]` extra for
  the `trino.sqlalchemy` dialect GX needs.

**API verified against the current docs, not recalled from training data.**
GX's Python API changed substantially across major versions (the old
`context.sources.add_*` / `ExpectationSuite` YAML-config style from GX 0.x is
gone in 1.x). Fetched `docs.greatexpectations.io/docs/core/introduction/try_gx`
directly — it's versioned to 1.20.0 at the top of the page, so this is
current, not stale — and copied the documented SQL-table workflow shape
exactly: `context.data_sources.add_sql(name, connection_string=...)` ->
`data_source.add_table_asset(...)` -> `add_batch_definition_whole_table(...)`
-> `context.suites.add(ExpectationSuite(...))` -> `suite.add_expectation(...)`
-> `context.validation_definitions.add(ValidationDefinition(...))` ->
`context.checkpoints.add(Checkpoint(...))` -> `checkpoint.run()`.

Also checked `docs.greatexpectations.io/docs/help/compatibility_reference` —
Trino is explicitly listed as a supported data source (not just "should work
via generic SQLAlchemy"), and confirmed the `trino://user@host:port/catalog/schema`
connection-string format via a WebSearch hit rather than assuming it matched
Postgres's format.

## Decision
**Target `iceberg.gold.gold_order_summary` specifically**, not Silver, and
picked expectations that are genuinely distinct from what layers 1/2 already
cover, not duplicates:
- `order_id` not null + unique (defense in depth — dbt already tests this,
  but GX validates the actual queryable table state independently)
- `customer_id` not null
- `status` in `{'placed', 'shipped', 'delivered', 'cancelled'}` — the
  intentional failure target, since nothing else in the stack checks this
- `total_amount_cents` >= 0
- `item_count` >= 0

Connection: `trino://gx@trino:8080/iceberg/gold` — same host/port/no-auth
pattern as `dbt/profiles.yml` (`method: none`), reusing infrastructure
already proven to work rather than inventing a new connection path.

**Script, not notebook or persisted GX project.** `gx.get_context()` with no
arguments creates an ephemeral in-memory context (confirmed from the same
`try_gx` doc — no `great_expectations.yml` is created or read). This matches
how `dbt` runs in this repo: a container invoked with `docker compose run`,
not a long-lived service. `run_checkpoint.py` is bind-mounted into the
`great-expectations` image at runtime (same pattern as `dbt/cdc_lakehouse`
being mounted rather than baked into the dbt image) so the suite can change
without a rebuild.

**Exit code carries the result.** `sys.exit(1)` on `checkpoint_result.success
== False` — this is what will let CI (task not yet started) fail a pipeline
run on a real data-quality violation, not just a human reading terminal
output.

## Consequences
- `docker compose run --rm great-expectations` only produces a meaningful
  result if `docker compose run --rm dbt run` has already built
  `gold_order_summary` — the compose `depends_on: dbt` relationship only
  waits for the dbt container to exit (default command `--version`), it does
  not track whether models were actually built. Documented directly in the
  compose file comment to avoid the false impression that depends_on implies
  data-readiness.
- No Iceberg-native GX integration exists to fall back on if the Trino path
  ever breaks — same single-point-of-query-access tradeoff dbt already
  accepted (ADR 0009), now shared by a second tool.
- Follow-up: the genuine-failure demo (portfolio asset 08) requires actually
  writing a bad `status` value into Postgres and letting it flow through
  Bronze -> Silver -> Gold before running the checkpoint — not yet done as of
  this ADR, tracked as its own task.
