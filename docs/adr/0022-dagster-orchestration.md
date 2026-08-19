# ADR 0022: Dagster orchestration — dbt + Great Expectations as one asset graph

Status: Accepted
Date: 2026-08-18

## Context
ADR 0003 chose Dagster over Airflow at the start of this project, on the
premise that Software-Defined Assets model "each Iceberg table is a
contracted asset with lineage" more directly than task-based DAGs. Tier 0/1
work since then built dbt (ADR 0009/0011) and Great Expectations (ADR 0020)
as separately-invoked containers (`docker compose run --rm dbt run`, `...
great-expectations`). This ADR wires both into one Dagster asset graph
without deprecating either standalone command.

**Dagster's CLI/tooling changed meaningfully since ADR 0003 was written**,
so the actual implementation approach needed re-verifying against current
docs rather than assumed:

- The `dagster` CLI (`dagster dev`, `dagster-webserver -f ...`) is now
  labeled "superseded" in favor of a newer `dg` CLI, built around
  `create-dagster`-scaffolded projects (`pyproject.toml` + `src/<pkg>/`
  layout, managed with `uv`). Confirmed via the current CLI reference page
  (`docs.dagster.io/api/clis/cli`) that the classic flags still work
  identically, just without the new branding — `dg` is recommended for new
  *host-filesystem* projects, but this repo's pattern is Docker-first
  (every other tool here is a thin image + mounted script, not a
  host-managed project directory). Chose to keep the classic
  `Definitions` object + `dagster-webserver -f definitions.py` approach
  rather than adopt `uv`/`dg` scaffolding, since it needs nothing beyond a
  plain Python file and fits the existing Dockerfile pattern exactly.
- No maintained first-party Dagster+Great-Expectations integration package
  exists for GX Core 1.x. `dagster-ge` (the old package still findable in
  search results) was built against GX's pre-1.0 API, which — per ADR
  0020's own research — was substantially reworked. Confirmed the current
  documented pattern is a hand-written `@asset_check` that calls GX
  directly and returns `AssetCheckResult`, not a wrapper library. This is
  also a better fit conceptually: Dagster's asset-check primitive models
  "validate this asset's data" more precisely than shoehorning GX into a
  second downstream asset node would.

**Versions pinned from real sources, not memory**: `dagster` 1.13.18 and
`dagster-dbt` 0.29.18, both released 2026-08-14 (confirmed via
`libraries.io/pypi/dagster-dbt` and cross-checked against the version
switcher on `docs.dagster.io` itself, which showed "Latest (1.13.17)" one
patch behind the PyPI listing — docs lag package releases slightly here,
not a discrepancy worth chasing further).

## Decision
**Verified the actual `dagster_dbt`/`great_expectations` API surface by
installing both packages in a throwaway virtualenv and running the real
code against the real dbt project** (`dbt/cdc_lakehouse`, copied into a
scratch directory) before writing anything into the compose stack —
consistent with this project's standing discipline (Apicurio, GX, trino-
init all did this) of confirming behavior against the primary source
instead of the first plausible-looking snippet. Concretely:

- `DbtProject(project_dir=..., profiles_dir=...).prepare_if_dev()` really
  does run `dbt parse --quiet` and produce a working `manifest.json`
  *without* needing a live Trino connection — confirmed by running it
  against this project's actual `profiles.yml` (host `trino`, unreachable
  from the verification sandbox) and getting a valid manifest anyway. This
  matters because the Dagster container starts before Trino necessarily
  has current data, and dbt's `parse` step only needs the profile to be
  syntactically valid, not reachable.
- `DbtCliResource(project_dir=dbt_project)` accepts the `DbtProject`
  instance directly (not just a raw path) — confirmed by successfully
  loading a full `Definitions` object with `dagster definitions validate`.
- The real Dagster asset key for the Gold model is `gold/gold_order_summary`
  (schema/model-name), not just `gold_order_summary` — confirmed by loading
  the actual manifest and printing
  `defs.resolve_asset_graph().get_all_asset_keys()`, rather than guessing
  from the model name. `bronze/customers`, `bronze/products`, `bronze/orders`,
  `bronze/order_items` also appear automatically as source assets (from
  `sources.yml`), giving the lineage graph the full Bronze -> Silver -> Gold
  chain for free.
- `@asset_check(asset=["gold", "gold_order_summary"], blocking=True)` and
  `AssetCheckResult(passed=..., metadata=...)` both validated end-to-end in
  the same throwaway environment.

**GX suite duplicated, not imported, between `great_expectations/
run_checkpoint.py` and `dagster/definitions.py`.** Considered importing the
standalone script's suite-building function to avoid drift, but the two
run in separate Docker images with separately-pinned dependency sets (the
Dagster image additionally needs `dagster`/`dagster-dbt`/`dbt-trino`; the
standalone GX image intentionally stays minimal). Cross-image imports would
mean either merging the images (losing the standalone command's minimalism)
or a shared volume mount of Python source across unrelated services (fragile,
unlike this project's existing mount patterns which only ever share static
config, not code). Duplication is a small, explicit maintenance cost,
documented here so it isn't mistaken for an oversight if the two suites ever
drift.

## Consequences
- Dagster's UI (`localhost:3000`) becomes the demo's centerpiece lineage
  view — this is the `09-dagster-lineage-graph` portfolio asset.
- The dbt project directory (`dbt/cdc_lakehouse`) is now mounted read/write
  into three different containers (`dbt`, `great-expectations` indirectly
  via Trino, and now `dagster`) — no conflict expected since only `dbt`
  and `dagster` actually write to it (`target/manifest.json`), and both
  write the same file the same way (`dbt parse`/`dbt build`), but worth
  remembering if a future concurrent-run race ever produces a confusing
  manifest-timestamp mismatch.
- `DAGSTER_HOME` is a named volume (`dagster_home`), so run/materialization
  history survives container restarts — unlike `great-expectations`, which
  is a one-shot `docker compose run` job with no persistent state.

## Follow-up (bring-up)
The pre-launch API verification (throwaway virtualenv, real dbt project,
`dagster definitions validate`) caught everything about the *definitions*
being correct — but not a deployment-shape issue that only shows up when
actually running a workload. First real `docker compose up -d dagster` +
"Materialize all" click: the webserver came up healthy, the code location
loaded (`loadStatus: LOADED`, confirmed directly via a GraphQL query when
the browser UI itself got stuck on an unrelated rendering quirk — see
below), but the launched run sat in `Queued` indefinitely. Root cause:
`ENTRYPOINT ["dagster-webserver", ...]` only starts the webserver process.
Processing the run queue is the `dagster-daemon`'s job, and nothing was
running one. Fixed by switching the entrypoint to `dagster dev`, which
starts webserver + daemon together in one process — the officially
documented way to get a complete local deployment from a single command,
and a much better fit for a single-container setup than running two
separate entrypoint processes by hand.

Separately, and not a real bug: the very first page load of the Dagster UI
in one particular automated browser session got stuck on "Loading
definitions..." indefinitely, even though direct GraphQL queries against
the same backend (`{ workspaceOrError { ... } }`, `{ assetNodes { ... } }`)
returned correct, complete data instantly. A plain reload in a fresh tab
resolved it. Confirmed via the user's own separate browser window loading
correctly at the same time — isolated to that one automated tab's client-
side state, not the deployment. Worth remembering if it recurs: check the
GraphQL API directly before assuming the backend is broken.
