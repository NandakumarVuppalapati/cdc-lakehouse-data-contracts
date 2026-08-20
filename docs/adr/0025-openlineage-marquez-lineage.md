# ADR 0025: OpenLineage + Marquez — column-level lineage, real events not a mockup

Status: Accepted (design verified against Marquez's and openlineage-dbt's
own docs/source; **not yet run** — same caveat pattern as ADR 0023/0024)
Date: 2026-08-20

## Context
Dagster's asset graph (ADR 0022) already shows model-level lineage —
Bronze → Silver → Gold as boxes and arrows — but nothing in this stack
shows *column*-level lineage: which specific source columns feed which
specific Gold columns. That's the Tier 2 target this ADR covers.
OpenLineage is the open standard for this; Marquez is its reference
backend/UI, maintained by the same project that originated the spec.

Two integration points exist for a dbt+Trino stack: a `dbt-ol` wrapper
script (post-processes dbt's own artifacts after a run) and a Dagster
`openlineage-dagster` package (asset-centric events emitted from inside
Dagster's execution). Both were researched before choosing.

## Decision
**dbt-ol, not dagster-openlineage.** Three services added to
`docker-compose.yml`: `marquez-db` (own dedicated `postgres:14`, mirroring
Marquez's own reference compose file — confirmed against
`github.com/MarquezProject/marquez/blob/main/docker-compose.yml` before
writing this, not guessed), `marquez-api`
(`marquezproject/marquez:0.51.1`), `marquez-web`
(`marquezproject/marquez-web:0.51.1`) — `0.51.1` is the newest version tag
Docker Hub actually lists as pushed (not just `latest`, which happens to
point at the same digest).

`dbt/Dockerfile` now installs `openlineage-dbt==1.52.0` (latest on PyPI at
time of writing) alongside `dbt-trino`. `trino` is one of the adapters
`openlineage-dbt` explicitly lists as supported — confirmed against the
package's own README, not assumed (this project has been burned before by
assuming an artifact/adapter exists without checking — ADR 0006's Iceberg
runtime, ADR 0007's delisted Confluent Hub listing).

`dbt/run_with_metrics.py` (already the dbt image's `ENTRYPOINT` since ADR
0024) now routes `run`/`build`/`test`/`seed`/`snapshot` invocations through
`dbt-ol` instead of plain `dbt`; every other verb (`--version`, `debug`,
`deps`, ...) stays on plain `dbt`. `dbt-ol` is a post-processing wrapper
built around `target/run_results.json` and `target/manifest.json` — verbs
that never produce those artifacts aren't its intended use case, and
routing them through it anyway would be an unverified guess about how it
degrades, not a confirmed-safe behavior. After a successful `dbt-ol`
invocation, the script also runs a plain `dbt docs generate` — column-level
metadata in the *next* OpenLineage event requires `target/catalog.json` to
already exist (openlineage-dbt's own README: "Additional table and column
level metadata will be available if `catalog.json` ... will be found in
the target directory"), and `catalog.json` isn't otherwise produced by
`run`/`build`. This keeps every subsequent run's lineage event
column-complete without a separate manual step.

Transport is two environment variables on the `dbt` service:
`OPENLINEAGE_URL=http://marquez-api:5000` and
`OPENLINEAGE_NAMESPACE=cdc_lakehouse` — openlineage-dbt uses the
OpenLineage Python client under the hood, and these are that client's own
documented config surface, not dbt-ol-specific plumbing.

**Why not dagster-openlineage**: it's explicitly community-maintained
(confirmed via its own GitHub issues — "new integration maintainers are
needed"), and version-gated to Dagster ≥1.11.6 with separate provider
classes per Dagster version range, adding a real compatibility surface to
verify against whatever Dagster version this project already pins (ADR
0022). `dbt-ol` is dbt-scoped, self-contained, and this project's dbt
usage (both standalone `docker compose run --rm dbt ...` and Dagster's own
`DbtCliResource` invocation, which shells out to the same `dbt` binary
under the hood) already funnels through one wrapper script
(`run_with_metrics.py`) regardless of which caller triggered it — so
wiring lineage in at that one chokepoint covers both invocation paths for
free, without touching Dagster's own dependency set at all. Extending to
`dagster-openlineage` later, for asset-level (not just dbt-model-level)
lineage of the GX checkpoint step, is a legitimate follow-up, not
foreclosed by this decision.

**Health check**: Marquez's Dropwizard admin interface exposes
`/healthcheck` on the admin port (5001) — confirmed against Marquez's own
`README.md` ("browse to http://localhost:5001 ... admin interface exposes
helpful endpoints like `/healthcheck`") before writing this, same
verify-the-real-endpoint discipline as ADR 0013 (Nessie) and ADR 0016
(Apicurio).

**Ports**: `marquez-db` host `5433` (5432 is the shared lakehouse
`postgres` service's mapping), `marquez-api` host `5000`/`5001` (both
free), `marquez-web` host `3002` (3000 is Dagster's, 3001 is Grafana's).
None of these host mappings matter to the stack itself — every internal
reference (`marquez-db:5432`, `marquez-api:5000`) goes over the Docker
network, same "host port only matters for a tool outside Docker" pattern
already established for kafka/trino/pushgateway in this file.

## A real bug caught while writing this
Re-reading the full `docker-compose.yml` before adding to it surfaced an
existing collision: `apicurio` already mapped host port `9091` (its
Quarkus admin port) and `pushgateway` (added later, ADR 0024) also mapped
host `9091`. Two services can't bind the same host port — `docker compose
up` would have failed with "port is already allocated" the first time the
user tried to bring the observability stack up. Fixed by moving
`pushgateway`'s host mapping to `9096` (container-internal port unchanged
at `9091` — Prometheus scrapes it at `pushgateway:9091` over the internal
network, so this has zero effect on anything inside the stack). Caught by
inspection, not by a failed run — worth noting because it means Tier 1
still had one undiscovered bug going into this session, despite being
marked "built."

## Alternatives considered
- **A single shared Postgres instance for Marquez** (reusing the
  lakehouse `postgres` service, the way `apicurio_registry` and `nessie`
  already do): rejected — Marquez's own reference deployment uses a
  dedicated Postgres, and reusing seemed likely to fight Marquez's schema
  migrations/expectations about owning its database outright rather than
  sharing an instance. Not worth the risk for a service whose whole job is
  being the system of record for lineage history.
- **openlineage-dagster for asset-level events**: see "Why not
  dagster-openlineage" above — deferred, not rejected outright.

## Consequences
- **Not yet run.** No live Docker daemon access from this session (same
  standing platform constraint as every prior ADR in this series) — this
  is built against confirmed image tags, a confirmed health endpoint, and
  documented (not guessed) `openlineage-dbt` behavior, but the first real
  `docker compose up -d marquez-db marquez-api marquez-web` followed by a
  real `docker compose run --rm dbt build` is the actual test. Likeliest
  failure points: whether `dbt-ol`'s exit code/stdout behavior differs
  from plain `dbt` in some way `run_with_metrics.py` doesn't already
  handle (it only inspects the subprocess return code, which should be
  robust to this), and whether the `OPENLINEAGE_NAMESPACE`/lineage graph
  actually renders column edges in the Marquez UI on the very first run
  (column data requires a *prior* `catalog.json` per the "why docs
  generate" note above — so the very first `dbt-ol build` after this
  change ships lineage events but not necessarily column detail; the
  second one should).
- `12-openlineage-graph.png` stays `[ ]` in `PORTFOLIO_ASSETS.md` until a
  real run produces a lineage graph worth screenshotting — ideally
  captured after at least two `dbt-ol build` invocations, for the reason
  above.
- Three more images/containers on top of the fifteen already in this
  stack — a real addition to `docker compose up -d`'s memory/startup
  footprint on a laptop, flagged the same way ADR 0024 flagged Prometheus/
  Grafana's addition.
